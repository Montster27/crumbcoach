import SwiftUI

// iPhone Settings — wraps the iPad `SettingsScreen` in a ScrollView with
// iPhone-appropriate padding. The iPad screen is already a vertical card
// stack capped at maxWidth 720, so it adapts to a narrower canvas without
// layout edits. Reusing avoids duplicating ~700 lines of profile / kitchen
// / cloud-sync / cloud-AI / sidekick / notifications / telemetry / data /
// about cards.
//
// If the iPhone density ever needs to diverge meaningfully from iPad
// (smaller card padding, list-style rows, segment per section), this is
// the file to fork into a real iPhone-native variant.

struct PhoneSettingsScreen: View {
    var state: AppState
    var body: some View {
        ScrollView {
            SettingsScreen(state: state)
                .padding(.horizontal, PhoneTheme.screenHPad)
                .padding(.top, PhoneTheme.screenVPad)
                .padding(.bottom, PhoneTheme.sectionSpacing)
        }
        .background(Theme.surface1)
    }
}

#Preview("Phone Settings") {
    NavigationStack {
        PhoneSettingsScreen(state: AppState(persistence: PersistenceController(filename: "preview-phone-settings.json")))
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
    }
}
