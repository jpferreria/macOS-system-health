import Foundation
import Darwin

public enum StorageCollector {
    public static func collectSystemStorage(
        aggregateReadBytesPerSec: Double,
        aggregateWriteBytesPerSec: Double
    ) -> StorageSystemMetrics {
        let rootURL = URL(fileURLWithPath: "/")
        var volumeName = "Macintosh HD"
        var totalBytes: UInt64 = 0
        var availableBytes: UInt64 = 0

        if let values = try? rootURL.resourceValues(forKeys: [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ]) {
            if let name = values.volumeName {
                volumeName = name
            }
            if let total = values.volumeTotalCapacity {
                totalBytes = UInt64(max(0, total))
            }
            if let importantAvail = values.volumeAvailableCapacityForImportantUsage {
                availableBytes = UInt64(max(0, importantAvail))
            } else if let basicAvail = values.volumeAvailableCapacity {
                availableBytes = UInt64(max(0, basicAvail))
            }
        }

        // Fallback to statfs if URLResourceValues didn't populate
        if totalBytes == 0 {
            var fs = statfs()
            if statfs("/", &fs) == 0 {
                let blockSize = UInt64(fs.f_bsize)
                totalBytes = fs.f_blocks * blockSize
                availableBytes = fs.f_bavail * blockSize
            }
        }

        let usedBytes = totalBytes > availableBytes ? (totalBytes - availableBytes) : 0

        return StorageSystemMetrics(
            volumeName: volumeName,
            totalDiskBytes: totalBytes,
            availableDiskBytes: availableBytes,
            usedDiskBytes: usedBytes,
            aggregateReadBytesPerSec: aggregateReadBytesPerSec,
            aggregateWriteBytesPerSec: aggregateWriteBytesPerSec
        )
    }
}
