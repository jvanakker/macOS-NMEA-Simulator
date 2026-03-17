//
//  NMEA_SimulatorTests.swift
//  NMEA SimulatorTests
//
//  Created by Jip van Akker on 10/03/2026.
//

import Foundation
import Testing
@testable import NMEA_Simulator

struct NMEA_SimulatorTests {

    @Test func defaultResetPositionEncodesExpectedNMEACoordinates() async throws {
        let state = SimulatedGPSState(
            latitude: 52.0907,
            longitude: 5.1214,
            altitudeMeters: 14.0,
            speedKilometersPerHour: 0.0,
            courseDegrees: 0.0,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let sentences = NMEASentenceGenerator.sentences(from: state)
        let rmcFields = sentenceFields(sentences[0])
        let ggaFields = sentenceFields(sentences[1])

        // RMC: $GPRMC,time,status,lat,NS,lon,EW,...
        #expect(rmcFields[3] == "5205.4420")
        #expect(rmcFields[4] == "N")
        #expect(rmcFields[5] == "00507.2840")
        #expect(rmcFields[6] == "E")

        // GGA: $GPGGA,time,lat,NS,lon,EW,...
        #expect(ggaFields[2] == "5205.4420")
        #expect(ggaFields[3] == "N")
        #expect(ggaFields[4] == "00507.2840")
        #expect(ggaFields[5] == "E")
    }

    @Test func coordinateFieldsContainNoWhitespace() async throws {
        let state = SimulatedGPSState(
            latitude: 52.0907,
            longitude: 5.1214,
            altitudeMeters: 14.0,
            speedKilometersPerHour: 0.0,
            courseDegrees: 0.0,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let sentences = NMEASentenceGenerator.sentences(from: state)
        let rmcFields = sentenceFields(sentences[0])
        let ggaFields = sentenceFields(sentences[1])

        #expect(!rmcFields[3].contains(" "))
        #expect(!rmcFields[5].contains(" "))
        #expect(!ggaFields[2].contains(" "))
        #expect(!ggaFields[4].contains(" "))
    }

    @Test func advanceAppliesClimbAndTurnRates() async throws {
        var state = SimulatedGPSState(
            latitude: 52.0907,
            longitude: 5.1214,
            altitudeMeters: 14.0,
            speedKilometersPerHour: 0.0,
            courseDegrees: 350.0,
            climbRateMetersPerSecond: 1.5,
            turnRateDegreesPerSecond: 20.0,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )

        state.advance(seconds: 2.0, movementEnabled: true)

        #expect(state.altitudeMeters == 17.0)
        #expect(state.courseDegrees == 30.0)
    }

    @Test func advanceAppliesWindOffsetWhenEnabled() async throws {
        var state = SimulatedGPSState(
            latitude: 0.0,
            longitude: 0.0,
            altitudeMeters: 0.0,
            speedKilometersPerHour: 0.0,
            courseDegrees: 0.0,
            windSimulationEnabled: true,
            windSpeedKilometersPerHour: 36.0,
            windDirectionFromDegrees: 0.0,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )

        state.advance(seconds: 1.0, movementEnabled: true)

        let expectedLatitude = -10.0 / 111_320.0
        #expect(abs(state.latitude - expectedLatitude) < 0.000000001)
        #expect(abs(state.longitude) < 0.000000001)
    }

    private func sentenceFields(_ sentence: String) -> [String] {
        sentence
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "*", maxSplits: 1)
            .first?
            .split(separator: ",")
            .map(String.init) ?? []
    }
}
