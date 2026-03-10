//
//  SimulatorCore.swift
//  NMEA Simulator
//
//  Created by Jip van Akker on 10/03/2026.
//

import Foundation

struct NMEASimulatorConfiguration {
    let host: String
    let port: UInt16
    let rateHz: Double
    let latitude: Double
    let longitude: Double
    let altitudeMeters: Double
    let speedKilometersPerHour: Double
    let courseDegrees: Double
    let movementEnabled: Bool
}

struct SimulatedGPSState {
    var latitude: Double
    var longitude: Double
    var altitudeMeters: Double
    var speedKilometersPerHour: Double
    var courseDegrees: Double
    var timestamp: Date
    var fixQuality: Int = 1
    var satellitesInUse: Int = 10
    var hdop: Double = 0.9

    mutating func advance(seconds: TimeInterval, movementEnabled: Bool) {
        timestamp = timestamp.addingTimeInterval(seconds)
        guard movementEnabled, speedKilometersPerHour > 0 else {
            return
        }

        let metersPerSecond = speedKilometersPerHour / 3.6
        let distanceMeters = metersPerSecond * seconds
        let courseRadians = courseDegrees * .pi / 180.0

        let northMeters = cos(courseRadians) * distanceMeters
        let eastMeters = sin(courseRadians) * distanceMeters

        latitude += northMeters / 111_320.0
        let metersPerLongitudeDegree = max(1.0, cos(latitude * .pi / 180.0) * 111_320.0)
        longitude += eastMeters / metersPerLongitudeDegree

        latitude = min(90.0, max(-90.0, latitude))
        if longitude > 180.0 {
            longitude -= 360.0
        } else if longitude < -180.0 {
            longitude += 360.0
        }
    }
}

enum NMEASentenceGenerator {
    static func sentences(from state: SimulatedGPSState) -> [String] {
        [
            rmcSentence(from: state),
            ggaSentence(from: state)
        ]
    }

    private static func rmcSentence(from state: SimulatedGPSState) -> String {
        let utcTime = formatUTC(date: state.timestamp, format: "HHmmss.SS")
        let utcDate = formatUTC(date: state.timestamp, format: "ddMMyy")
        let latitude = formatCoordinate(state.latitude, isLatitude: true)
        let longitude = formatCoordinate(state.longitude, isLatitude: false)
        let speedInKnots = state.speedKilometersPerHour / 1.852
        let speed = formatDecimal(speedInKnots, fractionDigits: 1)
        let course = formatDecimal(state.courseDegrees, fractionDigits: 1)

        let body = "GPRMC,\(utcTime),A,\(latitude.value),\(latitude.direction),\(longitude.value),\(longitude.direction),\(speed),\(course),\(utcDate),,,A"
        return wrapWithChecksum(body: body)
    }

    private static func ggaSentence(from state: SimulatedGPSState) -> String {
        let utcTime = formatUTC(date: state.timestamp, format: "HHmmss.SS")
        let latitude = formatCoordinate(state.latitude, isLatitude: true)
        let longitude = formatCoordinate(state.longitude, isLatitude: false)
        let hdop = formatDecimal(state.hdop, fractionDigits: 1)
        let altitude = formatDecimal(state.altitudeMeters, fractionDigits: 1)

        let body = "GPGGA,\(utcTime),\(latitude.value),\(latitude.direction),\(longitude.value),\(longitude.direction),\(state.fixQuality),\(String(format: "%02d", state.satellitesInUse)),\(hdop),\(altitude),M,0.0,M,,"
        return wrapWithChecksum(body: body)
    }

    private static func formatUTC(date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    private static func formatDecimal(_ value: Double, fractionDigits: Int) -> String {
        String(format: "%.\(fractionDigits)f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func formatCoordinate(_ value: Double, isLatitude: Bool) -> (value: String, direction: String) {
        let absolute = abs(value)
        let degrees = Int(absolute)
        let minutes = (absolute - Double(degrees)) * 60.0
        let minuteComponent = String(format: "%07.4f", locale: Locale(identifier: "en_US_POSIX"), minutes)

        if isLatitude {
            let direction = value >= 0 ? "N" : "S"
            return (String(format: "%02d%@", degrees, minuteComponent), direction)
        } else {
            let direction = value >= 0 ? "E" : "W"
            return (String(format: "%03d%@", degrees, minuteComponent), direction)
        }
    }

    private static func wrapWithChecksum(body: String) -> String {
        let checksum = body.utf8.reduce(0, ^)
        return "$\(body)*\(String(format: "%02X", checksum))\r\n"
    }
}
