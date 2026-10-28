import SwiftUI

public struct ThresholdSettingsView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Label("Critical Alert Thresholds & Engine Configuration", systemImage: "slider.horizontal.3")
                        .font(.title2.bold())
                    Spacer()
                    Button("Reset to Defaults") {
                        appState.config = .default
                        appState.showFeedback("Threshold rules restored to recommended defaults.")
                    }
                    .buttonStyle(.bordered)
                }

                // 1. General & Notifications
                settingsGroup(title: "Sampling & Notifications", icon: "bell.badge.fill") {
                    sliderRow(
                        label: "Polling Interval",
                        value: $appState.config.pollingIntervalSeconds,
                        range: 1.0...10.0,
                        step: 0.5,
                        unit: "sec"
                    )
                    Toggle("Enable Native macOS Push Notifications for Critical Issues", isOn: $appState.config.enablePushNotifications)
                        .font(.callout)
                }

                // 2. Memory Thresholds
                settingsGroup(title: "Memory Critical Thresholds", icon: "memorychip.fill") {
                    sliderRow(
                        label: "Process Memory Critical Footprint",
                        value: $appState.config.processMemoryCriticalMB,
                        range: 512...16384,
                        step: 256,
                        unit: "MB"
                    )
                    sliderRow(
                        label: "Process Memory Warning Footprint",
                        value: $appState.config.processMemoryWarningMB,
                        range: 256...8192,
                        step: 256,
                        unit: "MB"
                    )
                    sliderRow(
                        label: "Memory Leak Growth Rate (Critical)",
                        value: $appState.config.processMemoryGrowthCriticalMBPerMin,
                        range: 100...2000,
                        step: 50,
                        unit: "MB/min"
                    )
                    sliderRow(
                        label: "System Swap Usage Critical Limit",
                        value: $appState.config.swapUsageCriticalGB,
                        range: 1.0...32.0,
                        step: 1.0,
                        unit: "GB"
                    )
                }

                // 3. Storage Thresholds
                settingsGroup(title: "Storage & Disk I/O Thresholds", icon: "internaldrive.fill") {
                    sliderRow(
                        label: "Low Disk Space Critical Alert",
                        value: $appState.config.diskFreeCriticalPercent,
                        range: 2.0...20.0,
                        step: 1.0,
                        unit: "% Free"
                    )
                    sliderRow(
                        label: "Low Disk Space Warning Alert",
                        value: $appState.config.diskFreeWarningPercent,
                        range: 5.0...35.0,
                        step: 1.0,
                        unit: "% Free"
                    )
                    sliderRow(
                        label: "Process Disk Write Thrashing Limit",
                        value: $appState.config.processDiskWriteCriticalMBps,
                        range: 10.0...500.0,
                        step: 10.0,
                        unit: "MB/s"
                    )
                }

                // 4. Network Thresholds
                settingsGroup(title: "Network Anomaly Thresholds", icon: "network") {
                    sliderRow(
                        label: "Process Upload Spike (Critical)",
                        value: $appState.config.processNetTxCriticalMBps,
                        range: 1.0...100.0,
                        step: 1.0,
                        unit: "MB/s"
                    )
                    sliderRow(
                        label: "Process Download Spike (Warning)",
                        value: $appState.config.processNetRxCriticalMBps,
                        range: 5.0...200.0,
                        step: 5.0,
                        unit: "MB/s"
                    )
                    sliderRow(
                        label: "TCP Retransmission Storm Limit",
                        value: $appState.config.tcpRetransmitCriticalPerSec,
                        range: 5.0...200.0,
                        step: 5.0,
                        unit: "re-tx/s"
                    )
                }

                // 5. Battery & Energy Thresholds
                settingsGroup(title: "Battery & Energy Impact Thresholds", icon: "battery.100.bolt") {
                    sliderRow(
                        label: "Rapid Battery Discharge Rate (Unplugged)",
                        value: $appState.config.batteryDischargeCriticalWatts,
                        range: 10.0...60.0,
                        step: 2.0,
                        unit: "Watts"
                    )
                    sliderRow(
                        label: "Runaway Process CPU %",
                        value: $appState.config.processCPUOnBatteryCriticalPercent,
                        range: 50.0...400.0,
                        step: 10.0,
                        unit: "% CPU"
                    )
                    sliderRow(
                        label: "Battery Health Service Warning",
                        value: $appState.config.batteryHealthWarningPercent,
                        range: 60.0...95.0,
                        step: 1.0,
                        unit: "% Health"
                    )
                }
            }
            .padding(20)
        }
    }

    private func settingsGroup<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func sliderRow(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        unit: String
    ) -> some View {
        HStack {
            Text(label)
                .font(.callout)
                .frame(width: 280, alignment: .leading)
            Slider(value: value, in: range, step: step)
            Text(String(format: "%.1f %@", value.wrappedValue, unit))
                .font(.system(.callout, design: .monospaced).bold())
                .frame(width: 110, alignment: .trailing)
        }
    }
}
