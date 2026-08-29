import Foundation

#if os(iOS)
import MediaPlayer

/// iOS 15 / legacy CarPlay browse support.
///
/// TrollStore devices can be discovered through the historical
/// `com.apple.developer.playable-content` entitlement even when CarPlay never
/// connects a `CPTemplateApplicationScene`. In that mode the system builds the
/// entire browse UI from MPPlayableContentManager, so this data source must be
/// registered as soon as the application process launches.
public enum KumoneLegacyCarPlay {
    public static func start() {
        LegacyCarPlayManager.shared.start()
    }
}

private final class LegacyCarPlayManager: NSObject,
    MPPlayableContentDataSource, MPPlayableContentDelegate {

    static let shared = LegacyCarPlayManager()

    private enum Action: Int, CaseIterable {
        case daily
        case fm
        case recent
        case liked

        var identifier: String {
            switch self {
            case .daily: return "kumone.daily"
            case .fm: return "kumone.fm"
            case .recent: return "kumone.recent"
            case .liked: return "kumone.liked"
            }
        }

        var title: String {
            switch self {
            case .daily: return String(localized: "每日推荐")
            case .fm: return String(localized: "私人漫游")
            case .recent: return String(localized: "最近播放")
            case .liked: return String(localized: "我喜欢的音乐")
            }
        }

        var subtitle: String {
            switch self {
            case .daily: return String(localized: "播放今天的每日推荐")
            case .fm: return String(localized: "按你的口味随机播放")
            case .recent: return String(localized: "继续最近听过的歌曲")
            case .liked: return String(localized: "播放收藏的歌曲")
            }
        }
    }

    private func start() {
        let manager = MPPlayableContentManager.shared()
        manager.dataSource = self
        manager.delegate = self
        manager.beginUpdates()
        manager.endUpdates()
        manager.reloadData()
    }

    // MARK: MPPlayableContentDataSource

    func numberOfChildItems(at indexPath: IndexPath) -> Int {
        indexPath.isEmpty ? Action.allCases.count : 0
    }

    func contentItem(at indexPath: IndexPath) -> MPContentItem? {
        guard indexPath.count == 1,
              let action = Action(rawValue: indexPath[indexPath.startIndex]) else { return nil }

        let item = MPContentItem(identifier: action.identifier)
        item.title = action.title
        item.subtitle = action.subtitle
        item.isContainer = false
        item.isPlayable = true
        return item
    }

    func beginLoadingChildItems(
        at indexPath: IndexPath,
        completionHandler: @escaping (Error?) -> Void
    ) {
        completionHandler(nil)
    }

    // MARK: MPPlayableContentDelegate

    func playableContentManager(
        _ contentManager: MPPlayableContentManager,
        initiatePlaybackOfContentItemAt indexPath: IndexPath,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard indexPath.count == 1,
              let action = Action(rawValue: indexPath[indexPath.startIndex]) else {
            completionHandler(Self.error("无法识别所选项目"))
            return
        }

        Task { @MainActor in
            do {
                try await play(action)
                completionHandler(nil)
            } catch {
                completionHandler(error)
            }
        }
    }

    @MainActor
    private func play(_ action: Action) async throws {
        await AccountStore.shared.bootstrap()

        switch action {
        case .daily:
            let tracks = try await NeteaseAPI.dailyRecommendSongs()
            guard !tracks.isEmpty else { throw Self.error("每日推荐暂时为空") }
            PlayerService.shared.play(tracks: tracks, source: .daily)

        case .fm:
            guard AccountStore.shared.hasAuthCookie else { throw Self.error("请先在 iPhone 上登录 Kumone") }
            PlayerService.shared.startFM()

        case .recent:
            guard let uid = AccountStore.shared.profile?.userId else {
                throw Self.error("请先在 iPhone 上登录 Kumone")
            }
            let records = try await NeteaseAPI.playRecords(uid: uid, week: false)
            let tracks = records.map(\.song)
            guard !tracks.isEmpty else { throw Self.error("最近播放暂时为空") }
            PlayerService.shared.play(tracks: tracks, source: .none)

        case .liked:
            guard let playlist = AccountStore.shared.likedSongsPlaylist else {
                throw Self.error("请先在 iPhone 上登录 Kumone")
            }
            let response = try await NeteaseAPI.playlistDetail(id: playlist.id)
            let tracks = response.playlist.tracks
            guard !tracks.isEmpty else { throw Self.error("喜欢的音乐暂时为空") }
            PlayerService.shared.play(tracks: tracks, source: .playlist(playlist.id))
        }
    }

    private static func error(_ message: String) -> NSError {
        NSError(
            domain: "KumoneLegacyCarPlay",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
#endif
