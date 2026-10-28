import SwiftUI

/// Overflow is a button rather than a slot, so no favorite loses its digit to it.
struct CompactFavoritesRow: View {
    /// `slot` is the favorite's place in the full section, which a skipped file can make differ.
    struct Favorite {
        let slot: Int
        let app: AppEntry
    }

    let favorites: [Favorite]
    let showsOverflow: Bool
    let onLaunch: (AppEntry) -> Void
    let onOverflow: () -> Void
    @Environment(\.metrics) private var metrics

    var body: some View {
        HStack(spacing: metrics.spacing.xs) {
            // Identified by the app, so a reorder moves an icon with its app, not by position.
            ForEach(favorites, id: \.app.id) { favorite in
                CompactFavoriteButton(help: help(for: favorite)) {
                    onLaunch(favorite.app)
                } content: {
                    // The result rows' size, so collapsing and expanding share one cached bitmap.
                    AppIconView(app: favorite.app, pointSize: metrics.size.resultRowIcon)
                        .frame(width: metrics.size.rowIcon, height: metrics.size.rowIcon)
                }
            }
            if showsOverflow {
                CompactFavoriteButton(help: "Show all  ↓", action: onOverflow) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(width: metrics.size.rowIcon, height: metrics.size.rowIcon)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Theme.Colors.controlSurface)
                                .padding(metrics.spacing.xxs)
                        )
                }
            }
        }
    }

    private func help(for favorite: Favorite) -> String {
        guard let digit = FavoriteSlots.digit(at: favorite.slot) else { return favorite.app.name }
        return "\(favorite.app.name)  ⌘\(digit)"
    }
}

/// One compact favorite: bare icon, tooltip, action; no hover chrome, so it reads tight.
private struct CompactFavoriteButton<Content: View>: View {
    let help: String
    let action: () -> Void
    @ViewBuilder let content: Content
    @Environment(\.metrics) private var metrics

    var body: some View {
        Button(action: action) {
            content
                .contentShape(RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
