//
//  SimulatorViewModel.swift
//  NMEA Simulator
//
//  Created by Jip van Akker on 10/03/2026.
//

import Foundation
import Combine

struct SimulatorLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let message: String

    var formattedTimestamp: String {
        Self.timestampFormatter.string(from: timestamp)
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

@MainActor
final class SimulatorViewModel: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var statusText = "Stopped"
    @Published private(set) var clientCount = 0
    @Published private(set) var sentencesSent = 0
    @Published private(set) var logEntries: [SimulatorLogEntry] = []

    private let server: TCPServerService
    private var activeConfiguration: NMEASimulatorConfiguration?
    private var state: SimulatedGPSState?
    private var tickerTask: Task<Void, Never>?
    private var lastTickDate: Date?
    private var sentenceLoggingEnabled = false
    private var movementEnabled = false

    init() {
        self.server = TCPServerService()
        bindServerCallbacks()
    }

    init(server: TCPServerService) {
        self.server = server
        bindServerCallbacks()
    }

    private func bindServerCallbacks() {
        server.onLog = { [weak self] message in
            Task { @MainActor in
                self?.appendLog(message)
            }
        }

        server.onClientCountChanged = { [weak self] count in
            Task { @MainActor in
                self?.clientCount = count
            }
        }

        server.onClientReady = { [weak self] clientID in
            Task { @MainActor in
                self?.sendCurrentFix(to: clientID)
            }
        }

        server.onFatalError = { [weak self] message in
            Task { @MainActor in
                self?.statusText = "Error"
                self?.appendLog(message)
                self?.stop(updateStatus: false)
            }
        }
    }

    func start(with configuration: NMEASimulatorConfiguration) {
        guard !isRunning else { return }

        do {
            try server.start(host: configuration.host, port: configuration.port)
        } catch {
            statusText = "Error"
            appendLog("Failed to start server: \(error.localizedDescription)")
            return
        }

        activeConfiguration = configuration
        state = SimulatedGPSState(
            latitude: configuration.latitude,
            longitude: configuration.longitude,
            altitudeMeters: configuration.altitudeMeters,
            speedKilometersPerHour: configuration.speedKilometersPerHour,
            courseDegrees: configuration.courseDegrees,
            timestamp: Date()
        )
        movementEnabled = configuration.movementEnabled
        sentencesSent = 0
        isRunning = true
        lastTickDate = Date()
        let visibleEndpoint = endpointDisplayString(for: configuration)
        statusText = "Running on \(visibleEndpoint)"
        appendLog("Server started on \(visibleEndpoint)")

        startTicker()
    }

    func stop(updateStatus: Bool = true) {
        guard isRunning || tickerTask != nil else { return }

        tickerTask?.cancel()
        tickerTask = nil
        server.stop()

        isRunning = false
        if updateStatus {
            statusText = "Stopped"
        }
        clientCount = 0
        activeConfiguration = nil
        lastTickDate = nil
        state = nil
        movementEnabled = false
        appendLog("Server stopped.")
    }

    func clearLog() {
        logEntries.removeAll()
    }

    func setSentenceLoggingEnabled(_ enabled: Bool) {
        sentenceLoggingEnabled = enabled
    }

    func updateRuntimeControls(
        movementEnabled: Bool,
        speedKilometersPerHour: Double,
        courseDegrees: Double
    ) {
        self.movementEnabled = movementEnabled
        state?.speedKilometersPerHour = speedKilometersPerHour
        state?.courseDegrees = courseDegrees
    }

    func updateRuntimePosition(
        latitude: Double,
        longitude: Double,
        altitudeMeters: Double
    ) {
        state?.latitude = latitude
        state?.longitude = longitude
        state?.altitudeMeters = altitudeMeters
    }

    private func startTicker() {
        guard let configuration = activeConfiguration else { return }
        let intervalSeconds = max(0.05, 1.0 / configuration.rateHz)
        let sleepNanoseconds = UInt64(intervalSeconds * 1_000_000_000)

        tickerTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                self.emitTick()
                try? await Task.sleep(nanoseconds: sleepNanoseconds)
            }
        }
    }

    private func emitTick() {
        guard isRunning, var state, activeConfiguration != nil else { return }

        let now = Date()
        let elapsed = now.timeIntervalSince(lastTickDate ?? now)
        lastTickDate = now
        state.advance(seconds: elapsed, movementEnabled: movementEnabled)
        self.state = state

        let payload = NMEASentenceGenerator.sentences(from: state).joined()
        server.broadcast(payload)
        sentencesSent += 2

        if sentenceLoggingEnabled {
            let compactPayload = payload
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\r\n", with: " | ")
            appendLog("TX: \(compactPayload)")
        }
    }

    private func sendCurrentFix(to clientID: UUID) {
        guard let state else { return }
        let payload = NMEASentenceGenerator.sentences(from: state).joined()
        server.send(payload, to: clientID)
    }

    private func appendLog(_ message: String) {
        logEntries.append(SimulatorLogEntry(timestamp: Date(), message: message))
        if logEntries.count > 1000 {
            logEntries.removeFirst(logEntries.count - 1000)
        }
    }

    private func endpointDisplayString(for configuration: NMEASimulatorConfiguration) -> String {
        if configuration.host == "0.0.0.0" || configuration.host == "::" {
            let resolvedIP = LocalIPAddressResolver.activeIPAddress() ?? configuration.host
            return "\(resolvedIP):\(configuration.port)"
        }
        return "\(configuration.host):\(configuration.port)"
    }
}
