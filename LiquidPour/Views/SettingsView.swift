import BottleSortCore
import SwiftUI

/// Player preferences. Presented as a sheet on iOS and as the Settings window (⌘,) on the Mac.
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    /// Shows a Done button (sheet presentation).
    var showsDone = false

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Toggle(isOn: $settings.value.soundEnabled) {
                    Label("Sound Effects", systemImage: "speaker.wave.2")
                }
                .onChange(of: settings.value.soundEnabled) { _, on in
                    if on { SoundEngine.shared.play(.clink) } else { FeedbackPlayer.cancelPending(); SoundEngine.shared.stopAll() }
                }
                #if os(iOS)
                Toggle(isOn: $settings.value.hapticsEnabled) {
                    Label("Haptics", systemImage: "iphone.radiowaves.left.and.right")
                }
                #endif
            } header: {
                Text("Feedback")
            }

            Section {
                Toggle(isOn: $settings.value.colorRunesEnabled) {
                    Label("Color Runes", systemImage: "eye")
                }
                Picker(selection: $settings.value.reduceMotion) {
                    Text("System").tag(ReduceMotionPreference.system)
                    Text("On").tag(ReduceMotionPreference.always)
                    Text("Off").tag(ReduceMotionPreference.never)
                } label: {
                    Label("Reduce Motion", systemImage: "figure.walk.motion")
                }
            } header: {
                Text("Accessibility")
            } footer: {
                Text("Color Runes draw a symbol on every potion so colors can be told apart without relying on hue. Reduce Motion replaces the flying pour with a gentle level change; System follows your device setting.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if showsDone {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        #endif
    }
}
