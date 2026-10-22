import AmmuttaCore
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section(L10n.settingsWorkout) {
                    Picker(L10n.settingsWeightUnit, selection: $model.weightUnit) {
                        Text(L10n.unitKgName).tag(WeightUnit.kilograms)
                        Text(L10n.unitLbName).tag(WeightUnit.pounds)
                    }
                    Stepper(value: $model.defaultRestSeconds, in: Limits.restSeconds, step: 15) {
                        LabeledContent(L10n.settingsDefaultRest, value: Format.clock(model.defaultRestSeconds))
                    }
                }
                Section(L10n.settingsHeartRate) {
                    NavigationLink {
                        HeartRateSensorView()
                    } label: {
                        LabeledContent(L10n.settingsSensor, value: model.heartRate.sensorName ?? L10n.sensorNone)
                    }
                    .accessibilityIdentifier("settings.heartRate")
                }
                Section {
                    Button(L10n.settingsLanguage) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
                Section(L10n.settingsAbout) {
                    LabeledContent(L10n.settingsVersion, value: version)
                    Text(L10n.settingsTagline)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(L10n.tabSettings)
        }
    }
}
