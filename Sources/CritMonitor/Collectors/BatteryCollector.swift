import Foundation
import IOKit
import IOKit.ps

public enum BatteryCollector {
    public static func collectBatteryMetrics(totalCPUUsagePercent: Double) -> BatterySystemMetrics {
        let thermalState = ProcessInfo.processInfo.thermalState

        var hasBattery = false
        var isCharging = false
        var isPluggedIn = true
        var chargePercent: Double = 100.0
        var healthPercent: Double = 100.0
        var cycleCount: Int = 0
        var dischargeWatts: Double = 0.0
        var timeRemainingMinutes: Int? = nil

        // 1. Read standard IOPS Power Sources
        if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] {
            for ps in list {
                guard let desc = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any] else {
                    continue
                }
                if let type = desc[kIOPSTypeKey as String] as? String,
                   type == (kIOPSInternalBatteryType as String) {
                    hasBattery = true
                }
                if let powerSourceState = desc[kIOPSPowerSourceStateKey as String] as? String {
                    isPluggedIn = (powerSourceState == (kIOPSACPowerValue as String))
                }
                if let charging = desc[kIOPSIsChargingKey as String] as? Bool {
                    isCharging = charging
                }
                if let curCap = desc[kIOPSCurrentCapacityKey as String] as? Double,
                   let maxCap = desc[kIOPSMaxCapacityKey as String] as? Double,
                   maxCap > 0 {
                    chargePercent = min(100.0, max(0.0, (curCap / maxCap) * 100.0))
                }
                if let timeToEmpty = desc[kIOPSTimeToEmptyKey as String] as? Int, timeToEmpty > 0 {
                    timeRemainingMinutes = timeToEmpty
                }
            }
        }

        // 2. Query AppleSmartBattery IOService for CycleCount, Voltage, Amperage, and Health %
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if service != IO_OBJECT_NULL {
            defer { IOObjectRelease(service) }
            hasBattery = true

            var propsRef: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let props = propsRef?.takeRetainedValue() as? [String: Any] {
                if let cycles = props["CycleCount"] as? Int {
                    cycleCount = cycles
                }

                // Health % calculation from AppleRawMaxCapacity (or NominalChargeCapacity) vs DesignCapacity
                let designCap = (props["DesignCapacity"] as? Double) ?? 0
                let rawMaxCap = (props["AppleRawMaxCapacity"] as? Double)
                    ?? (props["NominalChargeCapacity"] as? Double)
                    ?? 0
                if designCap > 0 && rawMaxCap > 0 && rawMaxCap <= designCap * 1.2 {
                    healthPercent = min(100.0, (rawMaxCap / designCap) * 100.0)
                } else if let maxCapPercent = props["MaxCapacity"] as? Double, maxCapPercent <= 110 {
                    healthPercent = min(100.0, maxCapPercent)
                }

                // Live Wattage from Voltage (mV) * InstantAmperage (mA)
                let voltageMV = (props["Voltage"] as? Double) ?? 0
                let amperageMA = (props["InstantAmperage"] as? Double) ?? (props["Amperage"] as? Double) ?? 0
                if voltageMV > 0 && amperageMA != 0 {
                    let watts = abs(voltageMV * amperageMA) / 1_000_000.0
                    if !isPluggedIn || amperageMA < 0 {
                        dischargeWatts = watts
                    }
                }
            }
        }

        return BatterySystemMetrics(
            hasBattery: hasBattery,
            isCharging: isCharging,
            isPluggedIn: isPluggedIn,
            chargePercent: chargePercent,
            healthPercent: healthPercent,
            cycleCount: cycleCount,
            dischargeWatts: dischargeWatts,
            timeRemainingMinutes: timeRemainingMinutes,
            thermalState: thermalState,
            totalCPUUsagePercent: totalCPUUsagePercent
        )
    }
}
