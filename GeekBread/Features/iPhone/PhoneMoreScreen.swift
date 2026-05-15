import SwiftUI

// Catch-all menu for the four lower-traffic destinations that don't earn a
// top-level tab on iPhone: Scheduler, Starter, Diagnose, Settings. Each
// link pushes the corresponding placeholder/full screen onto the More
// tab's NavigationStack so the system back button restores the menu.

struct PhoneMoreScreen: View {
    var state: AppState

    var body: some View {
        List {
            Section {
                NavigationLink {
                    PhoneSchedulerScreen(state: state)
                        .navigationTitle("Scheduler")
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    moreRow(icon: "clock.fill", title: "Scheduler",
                            subtitle: "Plan a bake")
                }

                NavigationLink {
                    PhoneStarterScreen(state: state)
                        .navigationTitle("Starter")
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    moreRow(icon: "drop.fill", title: "Starter",
                            subtitle: "Feeding log + health check")
                }

                NavigationLink {
                    PhoneDiagnosticScreen(state: state)
                        .navigationTitle("Diagnose")
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    moreRow(icon: "camera.fill", title: "Diagnose",
                            subtitle: "Photograph and analyze your crumb")
                }
            }

            Section {
                NavigationLink {
                    PhoneSettingsScreen(state: state)
                        .navigationTitle("Settings")
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    moreRow(icon: "gear", title: "Settings",
                            subtitle: "Units, kitchen, notifications")
                }
            }

            Section {
                HStack(spacing: 6) {
                    Text("GeekBread for iPhone")
                        .font(Typography.ui(11, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                        .kerning(0.5)
                    Spacer()
                    Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1")")
                        .font(Typography.mono(11))
                        .foregroundStyle(Theme.slate500)
                }
                .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.surface1)
    }

    private func moreRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.primaryTint)
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.primary)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Typography.ui(15, weight: .medium))
                    .foregroundStyle(Theme.slate900)
                Text(subtitle)
                    .font(Typography.ui(11.5))
                    .foregroundStyle(Theme.slate500)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview("Phone More") {
    NavigationStack { PhoneMoreScreen(state: AppState(persistence: PersistenceController(filename: "preview-phone-more.json"))) }
}
