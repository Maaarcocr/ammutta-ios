import SwiftUI
import UIKit

/// Picks the Bluetooth heart-rate sensor. Scans only while this screen is open.
struct HeartRateSensorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    var body: some View {
        let source = model.heartRate
        List {
            switch source.status {
            case .bluetoothOff:
                Section { Text(L10n.sensorBluetoothOff) }
            case .denied:
                Section {
                    Text(L10n.sensorDenied)
                    Button(L10n.sensorOpenSettings) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
            case .unsupported:
                Section { Text(L10n.sensorUnsupported) }
            case .idle, .searching, .connected:
                EmptyView()
            }

            if let name = source.sensorName {
                Section(L10n.sensorMine) {
                    LabeledContent(name) {
                        Text(statusText(source))
                    }
                    Button(L10n.sensorForget, role: .destructive) {
                        source.forget()
                    }
                    .accessibilityIdentifier("sensor.forget")
                }
            }

            Section {
                ForEach(source.discovered.filter { $0.id != source.sensorID }) { sensor in
                    Button {
                        source.connect(sensor)
                    } label: {
                        HStack {
                            Text(sensor.name)
                            Spacer()
                            Image(systemName: "cellularbars", variableValue: sensor.signal)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.primary)
                    .accessibilityIdentifier("sensor.discovered")
                }
            } header: {
                HStack {
                    Text(L10n.sensorNearby)
                    Spacer()
                    ProgressView()
                }
            }
        }
        .navigationTitle(L10n.sensorTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { source.startScanning() }
        .onDisappear { source.stopScanning() }
    }

    private func statusText(_ source: any HeartRateSource) -> String {
        switch source.status {
        case .connected: source.bpm.map(L10n.bpm) ?? L10n.sensorConnected
        case .searching: L10n.sensorSearching
        default: ""
        }
    }
}
