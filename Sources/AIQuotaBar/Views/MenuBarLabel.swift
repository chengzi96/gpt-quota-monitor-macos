import SwiftUI

/// SwiftUI fallback/preview for the menu-bar label. The live app uses the native
/// NSStatusItem owned by StatusBarController so hover can open the popup.
struct MenuBarLabel: View {
    @EnvironmentObject private var store: QuotaStore
    @AppStorage("showMenuBarPercentage") private var showPercentage = true

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "hourglass")
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(store.menuBarColor)

            if showPercentage {
                Text(store.menuBarSummaryText)
                    .font(DesignTokens.menuBarFont)
                    .foregroundStyle(store.menuBarColor)
            }
        }
        .help(store.menuBarDetailedHelp)
    }
}
