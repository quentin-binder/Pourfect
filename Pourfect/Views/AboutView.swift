import SwiftUI

/// Version, credits and privacy note. Pushed from Settings on iOS, a sheet on the Mac.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    /// Shows a Done button (sheet presentation on the Mac).
    var showsDone = false

    /// "1.0 (12)" from the bundle's marketing version and build number.
    static var versionText: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 6) {
                    Image(systemName: "flask.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.teal, .orange)
                        .accessibilityHidden(true)
                    Text("Pourfect")
                        .font(.system(size: 28, weight: .bold, design: .serif))
                    Text("Version \(Self.versionText)", comment: "App version and build number, e.g. Version 1.0 (3)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
            }

            Section {
                Text("The paintings (workbench, chapter map, chapter scenes, characters, lab themes and the app icon) were generated with FLUX 1.1 [pro] Ultra by Black Forest Labs through Replicate. Character cut-outs use Bria's background removal. Both are used under their providers' commercial terms.", comment: "About screen: art credits and licensing note")
            } header: {
                Text("Art", comment: "About screen section header")
            }

            Section {
                Text("Every sound is synthesized by the app while you play; there are no recorded samples. Text uses Apple's system fonts (SF Pro, SF Pro Rounded and New York).", comment: "About screen: sound and font credits")
            } header: {
                Text("Sounds and Fonts", comment: "About screen section header")
            }

            Section {
                Text("Pourfect collects no data: no accounts, no ads, no analytics. Your progress is saved only on this device.", comment: "About screen: privacy note")
            } header: {
                Text("Privacy", comment: "About screen section header")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(Text("About", comment: "About screen title"))
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
        .frame(width: 460, height: 520)
        #endif
    }
}
