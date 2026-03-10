//
//  TCPServerService.swift
//  NMEA Simulator
//
//  Created by Jip van Akker on 10/03/2026.
//

import Foundation
import Network

enum TCPServerError: LocalizedError {
    case alreadyRunning
    case invalidPort

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "Server is already running."
        case .invalidPort:
            return "Invalid TCP port."
        }
    }
}

final class TCPServerService {
    var onLog: ((String) -> Void)?
    var onClientCountChanged: ((Int) -> Void)?
    var onClientReady: ((UUID) -> Void)?
    var onFatalError: ((String) -> Void)?

    private let queue = DispatchQueue(label: "nmea.simulator.tcpserver")
    private var listener: NWListener?
    private var clients: [UUID: NWConnection] = [:]

    func start(host: String, port: UInt16) throws {
        guard listener == nil else {
            throw TCPServerError.alreadyRunning
        }
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw TCPServerError.invalidPort
        }

        let parameters = NWParameters.tcp
        if host != "0.0.0.0", host != "::" {
            parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(host), port: nwPort)
        }

        let listener = try NWListener(using: parameters, on: nwPort)
        listener.stateUpdateHandler = { [weak self] state in
            self?.handleListenerState(state)
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }
        listener.start(queue: queue)

        self.listener = listener
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.listener?.cancel()
            self.listener = nil
            for (_, connection) in self.clients {
                connection.cancel()
            }
            self.clients.removeAll()
            self.dispatchClientCountUpdate()
        }
    }

    func broadcast(_ message: String) {
        let data = Data(message.utf8)
        queue.async { [weak self] in
            guard let self else { return }
            for (clientID, connection) in self.clients {
                self.send(data: data, to: connection, clientID: clientID)
            }
        }
    }

    func send(_ message: String, to clientID: UUID) {
        let data = Data(message.utf8)
        queue.async { [weak self] in
            guard let self, let connection = self.clients[clientID] else { return }
            self.send(data: data, to: connection, clientID: clientID)
        }
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            dispatchLog("TCP listener ready.")
        case .failed(let error):
            dispatchLog("Listener failed: \(error.localizedDescription)")
            dispatchFatalError("Listener failed: \(error.localizedDescription)")
            stop()
        case .cancelled:
            dispatchLog("TCP listener stopped.")
        default:
            break
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        let clientID = UUID()
        clients[clientID] = connection
        dispatchLog("Client opening: \(clientID.uuidString)")
        dispatchClientCountUpdate()

        connection.stateUpdateHandler = { [weak self] state in
            self?.handleConnectionState(state, clientID: clientID)
        }
        connection.start(queue: queue)
        receive(on: connection, clientID: clientID)
    }

    private func handleConnectionState(_ state: NWConnection.State, clientID: UUID) {
        switch state {
        case .ready:
            dispatchLog("Client connected: \(clientID.uuidString)")
            dispatchClientReady(clientID)
        case .failed(let error):
            dispatchLog("Client failed (\(clientID.uuidString)): \(error.localizedDescription)")
            removeClient(clientID)
        case .cancelled:
            dispatchLog("Client disconnected: \(clientID.uuidString)")
            removeClient(clientID)
        default:
            break
        }
    }

    private func receive(on connection: NWConnection, clientID: UUID) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { [weak self] _, _, isComplete, error in
            guard let self else { return }

            if isComplete || error != nil {
                self.removeClient(clientID)
                return
            }

            self.receive(on: connection, clientID: clientID)
        }
    }

    private func send(data: Data, to connection: NWConnection, clientID: UUID) {
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if let error {
                self.dispatchLog("Send error (\(clientID.uuidString)): \(error.localizedDescription)")
                self.removeClient(clientID)
            }
        })
    }

    private func removeClient(_ clientID: UUID) {
        guard let connection = clients.removeValue(forKey: clientID) else {
            return
        }
        connection.cancel()
        dispatchClientCountUpdate()
    }

    private func dispatchLog(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.onLog?(message)
        }
    }

    private func dispatchClientCountUpdate() {
        let count = clients.count
        DispatchQueue.main.async { [weak self] in
            self?.onClientCountChanged?(count)
        }
    }

    private func dispatchClientReady(_ clientID: UUID) {
        DispatchQueue.main.async { [weak self] in
            self?.onClientReady?(clientID)
        }
    }

    private func dispatchFatalError(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.onFatalError?(message)
        }
    }
}
