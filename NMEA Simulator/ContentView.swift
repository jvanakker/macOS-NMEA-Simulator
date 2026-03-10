//
//  ContentView.swift
//  NMEA Simulator
//
//  Created by Jip van Akker on 10/03/2026.
//

import SwiftUI
import MapKit

enum SimulatorConfigurationError: LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message):
            return message
        }
    }
}

struct ContentView: View {
    private static let defaultLatitude = 52.0907
    private static let defaultLongitude = 5.1214

    @StateObject private var viewModel = SimulatorViewModel()

    @AppStorage("sim.port") private var port = 10110
    @AppStorage("sim.rateHz") private var rateHz = 1.0
    @AppStorage("sim.latitude") private var latitude = ContentView.defaultLatitude
    @AppStorage("sim.longitude") private var longitude = ContentView.defaultLongitude
    @AppStorage("sim.altitudeMeters") private var altitudeMeters = 14.0
    @AppStorage("sim.speedKilometersPerHour") private var speedKilometersPerHour = 0.0
    @AppStorage("sim.courseDegrees") private var courseDegrees = 0.0
    @AppStorage("sim.climbRateMetersPerSecond") private var climbRateMetersPerSecond = 0.0
    @AppStorage("sim.turnRateDegreesPerSecond") private var turnRateDegreesPerSecond = 0.0
    @AppStorage("sim.isMoving") private var isMoving = false
    @AppStorage("sim.showSentencesInLog") private var showSentencesInLog = false

    @State private var validationMessage: String?
    @State private var isMapEditorPresented = false
    @State private var detectedLocalIPAddress = LocalIPAddressResolver.activeIPAddress() ?? "Unavailable"
    @State private var isLogInspectorPresented = true

    var body: some View {
        contentContainer
    }

    private var contentContainer: some View {
        let baseView = AnyView(
            mainLayout
                .padding()
                .frame(minWidth: 640, maxWidth: .infinity, minHeight: 520, maxHeight: .infinity)
                .toolbar {
                    ToolbarItemGroup(placement: .status) {
                        Button {
                            startServer()
                        } label: {
                            Label("Start Server", systemImage: "play.fill")
                        }
                        .disabled(viewModel.isRunning)
                        .help("Start the TCP NMEA server")

                        Button {
                            viewModel.stop()
                        } label: {
                            Label("Stop Server", systemImage: "stop.fill")
                        }
                        .disabled(!viewModel.isRunning)
                        .help("Stop the TCP NMEA server")
                    }

                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            viewModel.clearLog()
                        } label: {
                            Label("Clear Log", systemImage: "trash")
                        }
                        .help("Clear all log entries")

                        Button {
                            isLogInspectorPresented.toggle()
                        } label: {
                            Label("Log", systemImage: "sidebar.trailing")
                        }
                        .help(isLogInspectorPresented ? "Hide log panel" : "Show log panel")
                    }
                }
        )

        let observedView = AnyView(
            baseView
                .onAppear {
                    refreshLocalIPAddress()
                    viewModel.setSentenceLoggingEnabled(showSentencesInLog)
                }
                .onChange(of: showSentencesInLog) { _, newValue in
                    viewModel.setSentenceLoggingEnabled(newValue)
                }
                .onChange(of: rateHz) { _, _ in
                    applyRuntimeRateIfNeeded()
                }
                .onChange(of: isMoving) { _, _ in
                    applyRuntimeSettingsIfNeeded()
                }
                .onChange(of: speedKilometersPerHour) { _, _ in
                    applyRuntimeSettingsIfNeeded()
                }
                .onChange(of: courseDegrees) { _, _ in
                    applyRuntimeSettingsIfNeeded()
                }
                .onChange(of: climbRateMetersPerSecond) { _, _ in
                    applyRuntimeSettingsIfNeeded()
                }
                .onChange(of: turnRateDegreesPerSecond) { _, _ in
                    applyRuntimeSettingsIfNeeded()
                }
                .onChange(of: latitude) { _, _ in
                    applyRuntimePositionIfNeeded()
                }
                .onChange(of: longitude) { _, _ in
                    applyRuntimePositionIfNeeded()
                }
                .onChange(of: altitudeMeters) { _, _ in
                    applyRuntimePositionIfNeeded()
                }
                .onDisappear {
                    viewModel.stop()
                }
        )

        return AnyView(
            observedView
                .alert("Invalid Settings", isPresented: Binding(
                    get: { validationMessage != nil },
                    set: { _ in validationMessage = nil }
                )) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(validationMessage ?? "")
                }
                .sheet(isPresented: $isMapEditorPresented) {
                    StartPositionMapSheet(
                        initialCoordinate: currentStartCoordinate,
                        defaultCoordinate: CLLocationCoordinate2D(
                            latitude: Self.defaultLatitude,
                            longitude: Self.defaultLongitude
                        )
                    ) { coordinate in
                        latitude = coordinate.latitude
                        longitude = coordinate.longitude
                        applyRuntimePositionIfNeeded()
                    }
                }
                .inspector(isPresented: $isLogInspectorPresented) {
                    logInspector
                }
        )
    }

    private var mainLayout: some View {
        VStack(spacing: 16) {
            settingsForm
        }
    }

    private var settingsForm: some View {
        Form {
            networkSection
            gpsSection
            monitoringSection
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var networkSection: some View {
        Section("Network") {
            VStack(alignment: .leading, spacing: 10) {
                settingRow("Local IP") {
                    HStack(spacing: 8) {
                        Text(detectedLocalIPAddress)
                            .font(.system(.body, design: .monospaced))
                        Button("Refresh") {
                            refreshLocalIPAddress()
                        }
                    }
                }
                Text("Listening on all interfaces (0.0.0.0)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                settingRow("Port") {
                    TextField("", value: $port, format: .number.grouping(.never))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                        .disabled(viewModel.isRunning)
                }
                settingRow("Rate (Hz)") {
                    TextField("", value: $rateHz, format: .number.precision(.fractionLength(1...2)))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                }
            }
        }
    }

    private var gpsSection: some View {
        Section("GPS Source") {
            VStack(alignment: .leading, spacing: 10) {
                settingRow("Latitude") {
                    TextField("", value: $latitude, format: .number.precision(.fractionLength(4...6)))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 170)
                }
                settingRow("Longitude") {
                    TextField("", value: $longitude, format: .number.precision(.fractionLength(4...6)))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 170)
                }
                HStack {
                    Button("Set Start Position On Map") {
                        isMapEditorPresented = true
                    }

                    Button("Reset") {
                        latitude = Self.defaultLatitude
                        longitude = Self.defaultLongitude
                        applyRuntimePositionIfNeeded()
                    }

                    Spacer()
                }
                settingRow("Altitude (m)") {
                    TextField("", value: $altitudeMeters, format: .number.precision(.fractionLength(1...2)))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 170)
                }
                Toggle("Simulate Movement", isOn: $isMoving)
                settingRow("Speed (km/h)") {
                    TextField("", value: $speedKilometersPerHour, format: .number.precision(.fractionLength(1...2)))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 170)
                }
                settingRow("Course (degrees)") {
                    TextField("", value: $courseDegrees, format: .number.precision(.fractionLength(1...2)))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 170)
                }
                settingRow("Climb Rate (m/s)") {
                    TextField("", value: $climbRateMetersPerSecond, format: .number.precision(.fractionLength(1...2)))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 170)
                }
                settingRow("Turn Rate (deg/s)") {
                    TextField("", value: $turnRateDegreesPerSecond, format: .number.precision(.fractionLength(1...2)))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 170)
                }
            }
        }
    }

    private var monitoringSection: some View {
        Section("Monitoring") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Show Sentences In Log", isOn: $showSentencesInLog)
                settingRow("Status") {
                    Text(viewModel.statusText)
                        .foregroundStyle(.secondary)
                }
                settingRow("Clients") {
                    Text("\(viewModel.clientCount)")
                        .font(.system(.body, design: .monospaced))
                }
                settingRow("Sentences Sent") {
                    Text("\(viewModel.sentencesSent)")
                        .font(.system(.body, design: .monospaced))
                }
            }
        }
    }

    private var logInspector: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Log")
                .font(.headline)

            List(viewModel.logEntries) { entry in
                Text("\(entry.formattedTimestamp)  \(entry.message)")
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .textSelection(.enabled)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(.clear)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 1)
            )
        }
        .padding()
        .frame(minHeight: 260)
        .inspectorColumnWidth(min: 300, ideal: 440, max: 900)
    }

    @ViewBuilder
    private func settingRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer(minLength: 12)
            content()
        }
    }

    private func startServer() {
        do {
            let configuration = try buildConfiguration()
            viewModel.start(with: configuration)
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func buildConfiguration() throws -> NMEASimulatorConfiguration {
        guard (1...65535).contains(port) else {
            throw SimulatorConfigurationError.invalid("Port must be between 1 and 65535.")
        }
        guard rateHz > 0 else {
            throw SimulatorConfigurationError.invalid("Rate must be greater than 0 Hz.")
        }
        guard (-90.0...90.0).contains(latitude) else {
            throw SimulatorConfigurationError.invalid("Latitude must be between -90 and 90.")
        }
        guard (-180.0...180.0).contains(longitude) else {
            throw SimulatorConfigurationError.invalid("Longitude must be between -180 and 180.")
        }
        guard speedKilometersPerHour >= 0 else {
            throw SimulatorConfigurationError.invalid("Speed cannot be negative.")
        }
        guard (0.0...360.0).contains(courseDegrees) else {
            throw SimulatorConfigurationError.invalid("Course must be between 0 and 360 degrees.")
        }

        return NMEASimulatorConfiguration(
            host: "0.0.0.0",
            port: UInt16(port),
            rateHz: rateHz,
            latitude: latitude,
            longitude: longitude,
            altitudeMeters: altitudeMeters,
            speedKilometersPerHour: speedKilometersPerHour,
            courseDegrees: courseDegrees == 360 ? 0 : courseDegrees,
            climbRateMetersPerSecond: climbRateMetersPerSecond,
            turnRateDegreesPerSecond: turnRateDegreesPerSecond,
            movementEnabled: isMoving
        )
    }

    private func refreshLocalIPAddress() {
        detectedLocalIPAddress = LocalIPAddressResolver.activeIPAddress() ?? "Unavailable"
    }

    private func applyRuntimeSettingsIfNeeded() {
        guard viewModel.isRunning else {
            return
        }
        viewModel.updateRuntimeControls(
            movementEnabled: isMoving,
            speedKilometersPerHour: max(0, speedKilometersPerHour),
            courseDegrees: courseDegrees == 360 ? 0 : min(360, max(0, courseDegrees)),
            climbRateMetersPerSecond: climbRateMetersPerSecond,
            turnRateDegreesPerSecond: turnRateDegreesPerSecond
        )
    }

    private func applyRuntimeRateIfNeeded() {
        guard viewModel.isRunning else {
            return
        }
        let sanitizedRate = max(0.01, rateHz)
        if sanitizedRate != rateHz {
            rateHz = sanitizedRate
        }
        viewModel.updateRuntimeRateHz(sanitizedRate)
    }

    private func applyRuntimePositionIfNeeded() {
        guard viewModel.isRunning else {
            return
        }
        viewModel.updateRuntimePosition(
            latitude: min(90.0, max(-90.0, latitude)),
            longitude: min(180.0, max(-180.0, longitude)),
            altitudeMeters: altitudeMeters
        )
    }

    private var currentStartCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: min(90.0, max(-90.0, latitude)),
            longitude: min(180.0, max(-180.0, longitude))
        )
    }
}
