import SwiftUI

// Shared placeholder used by the iPhone tab/More-menu sub-screens until
// each gets its own dedicated layout in a follow-up PR. Renders the screen
// name + a friendly note so the iPhone shell is navigable end-to-end on
// day one without each surface being feature-complete.

struct PhonePlaceholderScreen: View {
    let title: String
    let blurb: String
    var iconSystemName: String = "hammer.fill"

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ZStack {
                    Circle().fill(Theme.primaryTint).frame(width: 64, height: 64)
                    Image(systemName: iconSystemName)
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(Theme.primary)
                }
                VStack(spacing: 6) {
                    Text(title)
                        .font(Typography.display(22, weight: .medium))
                        .foregroundStyle(Theme.slate900)
                    Text(blurb)
                        .font(Typography.ui(13))
                        .foregroundStyle(Theme.slate600)
                        .multilineTextAlignment(.center)
                }
                Text("Coming to iPhone soon")
                    .font(Typography.ui(11, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .kerning(0.6)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.primaryTint, in: Capsule())
            }
            .padding(.horizontal, PhoneTheme.screenHPad)
            .padding(.top, 36)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.surface1)
    }
}
