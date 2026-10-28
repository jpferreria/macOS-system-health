import Foundation
import Darwin

public struct RawProcessNetSample: Sendable {
    public let pid: pid_t
    public let bytesIn: UInt64
    public let bytesOut: UInt64
    public let tcpRetransmissions: UInt64
}

public struct RawInterfaceSample: Sendable {
    public let primaryInterface: String
    public let isConnected: Bool
    public let totalRxBytes: UInt64
    public let totalTxBytes: UInt64
    public let totalPacketErrors: UInt64
}

public enum NetworkCollector {
    /// Collects system-wide network counters across hardware/tunnel interfaces via getifaddrs
    public static func sampleSystemInterfaces() -> RawInterfaceSample {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let firstAddr = ifaddrPtr else {
            return RawInterfaceSample(
                primaryInterface: "en0",
                isConnected: false,
                totalRxBytes: 0,
                totalTxBytes: 0,
                totalPacketErrors: 0
            )
        }
        defer { freeifaddrs(firstAddr) }

        var totalRx: UInt64 = 0
        var totalTx: UInt64 = 0
        var totalErrors: UInt64 = 0
        var activePrimary = "en0"
        var hasActiveInterface = false
        var maxBytesOnInterface: UInt64 = 0

        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let ifa = cursor?.pointee {
            let name = String(cString: ifa.ifa_name)
            let flags = Int32(ifa.ifa_flags)
            let isUp = (flags & IFF_UP) != 0 && (flags & IFF_RUNNING) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0

            if isUp && !isLoopback, let addr = ifa.ifa_addr {
                if addr.pointee.sa_family == UInt8(AF_LINK), let dataPtr = ifa.ifa_data {
                    let ifData = dataPtr.assumingMemoryBound(to: if_data.self).pointee
                    let rx = UInt64(ifData.ifi_ibytes)
                    let tx = UInt64(ifData.ifi_obytes)
                    let errs = UInt64(ifData.ifi_ierrors) &+ UInt64(ifData.ifi_oerrors)

                    // Only sum physical/tunnel interfaces (en*, bridge*, pdp_ip*) to avoid double-counting utun + en0 unless primary
                    if name.hasPrefix("en") || name.hasPrefix("pdp_ip") {
                        totalRx &+= rx
                        totalTx &+= tx
                        totalErrors &+= errs
                        if (rx &+ tx) > maxBytesOnInterface {
                            maxBytesOnInterface = rx &+ tx
                            activePrimary = name
                        }
                    }
                } else if addr.pointee.sa_family == UInt8(AF_INET) || addr.pointee.sa_family == UInt8(AF_INET6) {
                    if name.hasPrefix("en") || name.hasPrefix("utun") {
                        hasActiveInterface = true
                    }
                }
            }
            cursor = ifa.ifa_next
        }

        return RawInterfaceSample(
            primaryInterface: activePrimary,
            isConnected: hasActiveInterface || (totalRx + totalTx > 0),
            totalRxBytes: totalRx,
            totalTxBytes: totalTx,
            totalPacketErrors: totalErrors
        )
    }

    /// Runs a single non-blocking snapshot of `/usr/bin/nettop -P -L 1 -J bytes_in,bytes_out,re-tx -x`
    /// to obtain per-PID cumulative bytes and TCP retransmissions under standard user permissions.
    public static func samplePerProcessNetwork() -> [pid_t: RawProcessNetSample] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        process.arguments = ["-P", "-L", "1", "-J", "bytes_in,bytes_out,re-tx", "-x"]

        let pipe = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return [:]
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else {
            return [:]
        }

        return parseNettopCSV(output)
    }

    public static func parseNettopCSV(_ csv: String) -> [pid_t: RawProcessNetSample] {
        var result = [pid_t: RawProcessNetSample]()
        let lines = csv.split(whereSeparator: \.isNewline)

        for line in lines {
            if line.hasPrefix(",") { continue } // Header row: ,bytes_in,bytes_out,re-tx,
            let columns = line.split(separator: ",", omittingEmptySubsequences: false)
            guard columns.count >= 4 else { continue }

            let procWithPid = columns[0]
            guard let lastDot = procWithPid.lastIndex(of: ".") else { continue }
            let pidString = procWithPid[procWithPid.index(after: lastDot)...]
            guard let pid = pid_t(pidString), pid > 0 else { continue }

            let bytesIn = UInt64(columns[1]) ?? 0
            let bytesOut = UInt64(columns[2]) ?? 0
            let retx = UInt64(columns[3]) ?? 0

            result[pid] = RawProcessNetSample(
                pid: pid,
                bytesIn: bytesIn,
                bytesOut: bytesOut,
                tcpRetransmissions: retx
            )
        }

        return result
    }
}
