//
//  LocalIPAddressResolver.swift
//  NMEA Simulator
//
//  Created by Jip van Akker on 10/03/2026.
//

import Foundation

enum LocalIPAddressResolver {
    static func activeIPAddress() -> String? {
        var addressList: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addressList) == 0, let firstAddress = addressList else {
            return nil
        }
        defer { freeifaddrs(addressList) }

        var candidates: [(priority: Int, address: String)] = []
        var pointer: UnsafeMutablePointer<ifaddrs>? = firstAddress

        while let interface = pointer?.pointee {
            defer { pointer = interface.ifa_next }

            guard let namePtr = interface.ifa_name,
                  let addrPtr = interface.ifa_addr else {
                continue
            }

            let flags = Int32(interface.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isRunning = (flags & IFF_RUNNING) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            guard isUp, isRunning, !isLoopback else {
                continue
            }

            let interfaceName = String(cString: namePtr)
            if isIgnored(interfaceName: interfaceName) {
                continue
            }

            let family = Int32(addrPtr.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else {
                continue
            }

            var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let length = socklen_t(addrPtr.pointee.sa_len)
            let result = getnameinfo(
                addrPtr,
                length,
                &hostBuffer,
                socklen_t(hostBuffer.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else {
                continue
            }

            let address = String(cString: hostBuffer)
            guard isUsable(address: address, family: family) else {
                continue
            }

            let priority = priorityFor(interfaceName: interfaceName, family: family)
            candidates.append((priority, address))
        }

        return candidates.sorted(by: { $0.priority < $1.priority }).first?.address
    }

    private static func isIgnored(interfaceName: String) -> Bool {
        interfaceName.hasPrefix("utun") ||
        interfaceName.hasPrefix("awdl") ||
        interfaceName.hasPrefix("llw") ||
        interfaceName.hasPrefix("lo")
    }

    private static func isUsable(address: String, family: Int32) -> Bool {
        if family == AF_INET {
            return !address.hasPrefix("169.254.")
        }
        if family == AF_INET6 {
            let lowercase = address.lowercased()
            return !lowercase.hasPrefix("fe80:")
        }
        return false
    }

    private static func priorityFor(interfaceName: String, family: Int32) -> Int {
        let isEthernetOrWiFi = interfaceName.hasPrefix("en")
        if family == AF_INET, isEthernetOrWiFi { return 0 }
        if family == AF_INET { return 1 }
        if family == AF_INET6, isEthernetOrWiFi { return 2 }
        return 3
    }
}
