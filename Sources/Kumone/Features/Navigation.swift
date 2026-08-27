import SwiftUI

private struct OpenLoginKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var openLogin: () -> Void {
        get { self[OpenLoginKey.self] }
        set { self[OpenLoginKey.self] = newValue }
    }
}

struct PlayerChromeModifier: ViewModifier {
    @EnvironmentObject private var player: PlayerService
    let detailWidth: CGFloat

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomTrailing) {
                PlayerBar()
                    .frame(width: detailWidth)
            }
            .overlay(alignment: .trailing) {
                rightPanel
            }
            .animation(AppAnimation.standard, value: player.activePanel)
    }

    @ViewBuilder
    private var rightPanel: some View {
        if let panel = player.activePanel {
            Group {
                switch panel {
                case .lyrics:
                    LyricsPanel()
                case .queue:
                    QueuePanel()
                }
            }
            .padding(.top, 12)
            .padding(.bottom, Theme.Layout.playerChromeClearance + 10)
            .padding(.trailing, 16)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }
}

enum SidebarItem: Hashable {
    case home
    case explore
    case fm
    case likedSongs
    case daily
    case recents
    case collections
    case cloud
    case playlist(Int)
}

enum Destination: Hashable {
    case playlist(Int)
    case album(Int)
    case artist(Int)
    case daily
    case toplists
    case recents
    case collections
    case cloud
    case search(String)
}

/// Renders a destination directly on iOS 15, where value-based navigation
/// and NavigationStack are unavailable.
private struct DestinationContent: View {
    let destination: Destination

    @ViewBuilder
    var body: some View {
        switch destination {
        case .playlist(let id):
            PlaylistDetailView(playlistID: id)
        case .album(let id):
            AlbumDetailView(albumID: id)
        case .artist(let id):
            ArtistDetailView(artistID: id)
        case .daily:
            DailySongsView()
        case .toplists:
            ToplistsView()
        case .recents:
            RecentsView()
        case .collections:
            CollectionsView()
        case .cloud:
            CloudView()
        case .search(let query):
            SearchView(query: query)
        }
    }
}

struct DestinationLink<Label: View>: View {
    let value: Destination
    @ViewBuilder let label: () -> Label

    var body: some View {
        #if os(iOS)
        NavigationLink {
            DestinationContent(destination: value)
                .playerContentInset()
        } label: {
            label()
        }
        #else
        NavigationLink(value: value) {
            label()
        }
        #endif
    }
}

/// Registers all shared navigation destinations on a stack.
struct DestinationsModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(iOS)
        content
        #else
        content.navigationDestination(for: Destination.self) { destination in
            DestinationContent(destination: destination)
                .playerContentInset()
            }
        #endif
    }
}

extension View {
    func playerChrome(detailWidth: CGFloat) -> some View {
        modifier(PlayerChromeModifier(detailWidth: detailWidth))
    }

    /// Pages clear the floating player bar with an explicit trailing
    /// `PlayerClearanceSpacer` in their scroll content; safeAreaPadding
    /// proved unreliable inside navigation stacks (#12).
    func playerContentInset() -> some View {
        self
    }

    func appDestinations() -> some View {
        modifier(DestinationsModifier())
    }
}

/// Trailing spacer for scrollable pages so the last row clears the
/// floating player bar.
struct PlayerClearanceSpacer: View {
    var body: some View {
        #if os(iOS)
        Color.clear.frame(height: 80) // mini player bar above the tab bar
        #else
        Color.clear.frame(height: Theme.Layout.playerChromeClearance + 8)
        #endif
    }
}
