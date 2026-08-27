import SwiftUI

#if os(iOS)
public struct IOSMainWindow: View {
    @StateObject private var player = PlayerService.shared
    @StateObject private var account = AccountStore.shared
    @StateObject private var settings = SettingsManager.shared
    @StateObject private var toasts = ToastCenter.shared
    @StateObject private var updater = IOSUpdater.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var selectedTab: IOSTab = .home
    @State private var showLogin = false
    public init() {}

    public var body: some View {
        Group {
            if UIDevice.current.userInterfaceIdiom == .pad {
                if #available(iOS 16.0, *) {
                    // Keep the native split view on newer iPads.
                    MainWindow()
                } else {
                    // NavigationSplitView does not exist on iOS 15.
                    tabInterface
                }
            } else {
                // iPhone / Compact screen: Tab view
                tabInterface
            }
        }
        .environmentObject(player)
        .environmentObject(account)
        .environmentObject(settings)
        .environmentObject(toasts)
        .tint(Theme.accent)
        .preferredColorScheme(settings.appearance.colorScheme)
        .environment(\.openLogin, { showLogin = true })
        .task {
            await account.bootstrap()
            // Quiet auto-check on launch: only surfaces a sheet if newer.
            IOSUpdater.shared.check(interactive: false)
        }
        .sheet(isPresented: $updater.showSheet) {
            IOSUpdaterSheet()
        }
        .sheet(isPresented: $showLogin) {
            LoginSheet()
                .environmentObject(account)
                .environmentObject(toasts)
        }
        .fullScreenCover(isPresented: $player.showNowPlaying) {
            NowPlayingView()
                .environmentObject(player)
                .environmentObject(account)
                .environmentObject(settings)
        }
        .overlay(alignment: .top) {
            if let toast = toasts.current {
                ToastView(toast: toast)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
            }
        }
        .animation(.spring(duration: 0.3), value: toasts.current)
    }

    private var tabInterface: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                NavigationView {
                    HomeView()
                        .appDestinations()
                }
                .navigationViewStyle(StackNavigationViewStyle())
                .tabItem {
                    Label("推荐", systemImage: "house.fill")
                }
                .tag(IOSTab.home)

                NavigationView {
                    ExploreView()
                        .appDestinations()
                }
                .navigationViewStyle(StackNavigationViewStyle())
                .tabItem {
                    Label("精选", systemImage: "square.grid.2x2.fill")
                }
                .tag(IOSTab.explore)

                NavigationView {
                    FMView()
                        .appDestinations()
                }
                .navigationViewStyle(StackNavigationViewStyle())
                .tabItem {
                    Label("漫游", systemImage: "wave.3.right.circle.fill")
                }
                .tag(IOSTab.fm)

                NavigationView {
                    SearchView(query: "")
                        .appDestinations()
                }
                .navigationViewStyle(StackNavigationViewStyle())
                .tabItem {
                    Label("搜索", systemImage: "magnifyingglass")
                }
                .tag(IOSTab.search)

                NavigationView {
                    IOSLibraryView(showLogin: $showLogin)
                        .appDestinations()
                }
                .navigationViewStyle(StackNavigationViewStyle())
                .tabItem {
                    Label("我的", systemImage: "person.crop.circle.fill")
                }
                .tag(IOSTab.library)
            }

            if player.hasCurrentTrack {
                IOSMiniPlayerBar()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 54)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(AppAnimation.standard, value: player.hasCurrentTrack)
    }
}

enum IOSTab: Hashable {
    case home, explore, fm, search, library
}

// MARK: - Mini player bar for iOS

struct IOSMiniPlayerBar: View {
    @EnvironmentObject private var player: PlayerService
    @EnvironmentObject private var account: AccountStore

    var body: some View {
        Button {
            withAnimation(AppAnimation.smooth) {
                player.showNowPlaying = true
            }
        } label: {
            HStack(spacing: 10) {
                CachedAsyncImage(url: player.currentTrack?.album.picUrl?.resizedImageURL(128))
                    .frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.currentTrack?.name ?? "")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(player.currentTrack?.artistNames ?? "")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.pressable)

                Button {
                    player.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.pressable)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - iOS Library View

struct IOSLibraryView: View {
    @Binding var showLogin: Bool
    @EnvironmentObject private var account: AccountStore
    @State private var showSettings = false
    @State private var showNewPlaylist = false
    @State private var newPlaylistName = ""

    var body: some View {
        List {
            // Profile / Login header
            Section {
                if let profile = account.profile {
                    HStack(spacing: 14) {
                        CachedAsyncImage(url: profile.avatarUrl?.resizedImageURL(128))
                            .frame(width: 52, height: 52)
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(profile.nickname)
                                    .font(.headline)
                                if profile.vipType > 0 {
                                    VIPBadge()
                                }
                            }
                            if let sig = profile.signature, !sig.isEmpty {
                                Text(sig)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    Button {
                        showLogin = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.system(size: 32))
                                .foregroundStyle(Theme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("登录网易云音乐")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text("同步我喜欢的音乐、歌单与每日推荐")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }

            if account.hasAuthCookie {
                Section("我的音乐") {
                    if let liked = account.likedSongsPlaylist {
                        DestinationLink(value: Destination.playlist(liked.id)) {
                            Label("我喜欢的音乐", systemImage: "heart.fill")
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    DestinationLink(value: Destination.daily) {
                        Label("每日推荐", systemImage: "calendar")
                    }
                    DestinationLink(value: Destination.recents) {
                        Label("最近播放", systemImage: "clock.fill")
                    }
                    DestinationLink(value: Destination.collections) {
                        Label("我的收藏", systemImage: "star.fill")
                    }
                    DestinationLink(value: Destination.cloud) {
                        Label("音乐云盘", systemImage: "icloud.fill")
                    }
                }

                if !account.createdPlaylists.isEmpty {
                    Section {
                        ForEach(account.createdPlaylists) { playlist in
                            DestinationLink(value: Destination.playlist(playlist.id)) {
                                HStack(spacing: 10) {
                                    CachedAsyncImage(url: playlist.coverURL?.resizedImageURL(80), animated: false)
                                        .frame(width: 32, height: 32)
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(playlist.name)
                                            .font(.system(size: 14))
                                            .lineLimit(1)
                                        Text("\(playlist.trackCount) 首")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text("创建的歌单")
                            Spacer()
                            Button {
                                showNewPlaylist = true
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                        }
                    }
                }

                if !account.subscribedPlaylists.isEmpty {
                    Section("收藏的歌单") {
                        ForEach(account.subscribedPlaylists) { playlist in
                            DestinationLink(value: Destination.playlist(playlist.id)) {
                                HStack(spacing: 10) {
                                    CachedAsyncImage(url: playlist.coverURL?.resizedImageURL(80), animated: false)
                                        .frame(width: 32, height: 32)
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(playlist.name)
                                            .font(.system(size: 14))
                                            .lineLimit(1)
                                        Text("\(playlist.trackCount) 首")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("我的")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationView {
                SettingsView()
                    .navigationTitle("设置")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("完成") {
                                showSettings = false
                            }
                        }
                    }
            }
            .navigationViewStyle(StackNavigationViewStyle())
        }
        .alert("新建歌单", isPresented: $showNewPlaylist) {
            TextField("歌单名称", text: $newPlaylistName)
            Button("创建") {
                let name = newPlaylistName.trimmingCharacters(in: .whitespaces)
                newPlaylistName = ""
                guard !name.isEmpty else { return }
                Task {
                    do {
                        try await NeteaseAPI.createPlaylist(name: name, isPrivate: false)
                        await account.refreshLibrary()
                        ToastCenter.shared.show(String(localized: "歌单已创建"))
                    } catch {
                        ToastCenter.shared.show(error.localizedDescription)
                    }
                }
            }
            Button("取消", role: .cancel) { newPlaylistName = "" }
        }
    }
}
#endif
