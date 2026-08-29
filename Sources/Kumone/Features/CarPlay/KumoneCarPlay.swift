import Foundation

#if os(iOS)
import CarPlay
import UIKit

// MARK: - Scene delegate

/// CarPlay 场景入口。
///
/// 由 `ios/Config/Info.plist` 的 `CPTemplateApplicationSceneSessionRoleApplication`
/// 以模块限定名 `KumoneCore.KumoneCarPlaySceneDelegate` 引用，因此本类必须 `public`。
/// 模板回调（CPListItem handler 等）虽然运行在主线程，但对编译器而言是非隔离
/// 上下文，访问 `@MainActor` 状态统一经 `MainActor.assumeIsolated` 完成。
public final class KumoneCarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    public func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        KumoneCarPlayBootstrap.connect(interfaceController)
    }

    public func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController
    ) {
        KumoneCarPlayBootstrap.disconnect(interfaceController)
    }
}

/// Public bridge used by the iOS application target's CarPlay scene delegate.
/// The first root is intentionally a single CPListTemplate: it is supported by
/// every template-based audio CarPlay implementation on iOS 15 and avoids a
/// tab-bar construction failure leaving the scene with a blank canvas.
public enum KumoneCarPlayBootstrap {
    public static func connect(_ interfaceController: CPInterfaceController) {
        CarPlayBridge.interfaceController = interfaceController
        interfaceController.setRootTemplate(
            KumoneCarPlayTemplates.rootList(), animated: false, completion: nil
        )

        Task { @MainActor in
            await AccountStore.shared.bootstrap()
        }
    }

    public static func disconnect(_ interfaceController: CPInterfaceController) {
        if CarPlayBridge.interfaceController === interfaceController {
            CarPlayBridge.interfaceController = nil
        }
    }
}

/// 全局 CarPlay 连接句柄（仅主线程访问；断开后置 nil）。
enum CarPlayBridge {
    static var interfaceController: CPInterfaceController?
}

// MARK: - List state holder

/// 持有列表模板及其分区引用，支持数据异步到达后原地刷新单个分区或整个列表。
/// 所有方法仅在主线程调用（创建于模板回调，更新于 @MainActor Task）。
final class CarPlayListState {
    let template: CPListTemplate
    private var sections: [CPListSection]

    init(title: String, sections: [CPListSection]) {
        self.sections = sections
        self.template = CPListTemplate(title: title, sections: sections)
    }

    func update(_ items: [CPListItem], at index: Int) {
        let header = sections[index].header
        sections[index] = CPListSection(items: items, header: header, sectionIndexTitle: nil)
        template.updateSections(sections)
    }

    func updateAll(_ newSections: [CPListSection]) {
        sections = newSections
        template.updateSections(sections)
    }
}

/// 歌曲集合与播放来源的一次性共享引用，避免每个列表项闭包各自拷贝整张列表。
final class CarPlayTrackBatch {
    let tracks: [Track]
    let source: PlaySource

    init(tracks: [Track], source: PlaySource) {
        self.tracks = tracks
        self.source = source
    }
}

// MARK: - Template factory

/// 构建 CarPlay 模板树。模板构建与数据加载分离：列表先以「加载中」占位展示，
/// 数据到达后原地刷新，失败时展示可点按重试的错误项。
/// 注意：iOS 26 SDK 中 CPListItem 不再提供带 handler 的构造器，handler 为属性赋值。
enum KumoneCarPlayTemplates {

    // MARK: Root

    static func root() -> CPTemplate {
        let homeTemplate = home()
        homeTemplate.tabTitle = String(localized: "推荐")
        homeTemplate.tabImage = UIImage(systemName: "house.fill")

        let libraryTemplate = library()
        libraryTemplate.tabTitle = String(localized: "我的音乐")
        libraryTemplate.tabImage = UIImage(systemName: "music.note.list")

        return CPTabBarTemplate(templates: [homeTemplate, libraryTemplate])
    }

    /// Conservative iOS 15 root. Library remains one tap away while avoiding
    /// CPTabBarTemplate as the very first template shown by older head units.
    static func rootList() -> CPListTemplate {
        let holder = CarPlayListState(title: String(localized: "Kumone"), sections: [
            CPListSection(
                items: [dailyItem(), fmItem(), recentItem(), libraryRootItem()],
                header: String(localized: "为你推荐"), sectionIndexTitle: nil
            ),
            CPListSection(items: [loadingItem()], header: String(localized: "推荐歌单"), sectionIndexTitle: nil),
            CPListSection(items: [loadingItem()], header: String(localized: "排行榜"), sectionIndexTitle: nil),
        ])

        reloadPersonalized(into: holder, at: 1)
        reloadToplists(into: holder, at: 2)
        return holder.template
    }

    // MARK: Home tab

    static func home() -> CPListTemplate {
        let holder = CarPlayListState(title: String(localized: "推荐"), sections: [
            CPListSection(
                items: [dailyItem(), fmItem(), recentItem()],
                header: String(localized: "为你推荐"), sectionIndexTitle: nil
            ),
            CPListSection(items: [loadingItem()], header: String(localized: "推荐歌单"), sectionIndexTitle: nil),
            CPListSection(items: [loadingItem()], header: String(localized: "排行榜"), sectionIndexTitle: nil),
        ])

        reloadPersonalized(into: holder, at: 1)
        reloadToplists(into: holder, at: 2)
        return holder.template
    }

    private static func reloadPersonalized(into holder: CarPlayListState, at index: Int) {
        Task { @MainActor in
            do {
                let lists = try await NeteaseAPI.personalizedPlaylists(limit: 12)
                holder.update(lists.map(playlistItem(_:)), at: index)
            } catch {
                holder.update(
                    [errorItem(error, retry: { reloadPersonalized(into: holder, at: index) })],
                    at: index
                )
            }
        }
    }

    private static func reloadToplists(into holder: CarPlayListState, at index: Int) {
        Task { @MainActor in
            do {
                let lists = try await NeteaseAPI.toplists()
                holder.update(lists.map(toplistItem(_:)), at: index)
            } catch {
                holder.update(
                    [errorItem(error, retry: { reloadToplists(into: holder, at: index) })],
                    at: index
                )
            }
        }
    }

    // MARK: Library tab

    static func library() -> CPListTemplate {
        let holder = CarPlayListState(title: String(localized: "我的音乐"), sections: [
            CPListSection(items: [loadingItem()], header: nil, sectionIndexTitle: nil),
        ])
        Task { @MainActor in
            // CarPlay 可能在 App 进程早已运行时才连接；刷新一次登录态与歌单。
            await AccountStore.shared.bootstrap()
            let account = AccountStore.shared
            guard account.hasAuthCookie else {
                holder.updateAll([CPListSection(items: [loginItem()], header: nil, sectionIndexTitle: nil)])
                return
            }
            var sections: [CPListSection] = []

            var mine: [CPListItem] = []
            if let liked = account.likedSongsPlaylist {
                mine.append(playlistItem(liked))
            }
            mine.append(dailyItem())
            mine.append(recentItem())
            sections.append(CPListSection(items: mine, header: String(localized: "我的音乐"), sectionIndexTitle: nil))

            if !account.createdPlaylists.isEmpty {
                sections.append(CPListSection(
                    items: account.createdPlaylists.map(playlistItem(_:)),
                    header: String(localized: "创建的歌单"), sectionIndexTitle: nil
                ))
            }
            if !account.subscribedPlaylists.isEmpty {
                sections.append(CPListSection(
                    items: account.subscribedPlaylists.map(playlistItem(_:)),
                    header: String(localized: "收藏的歌单"), sectionIndexTitle: nil
                ))
            }
            holder.updateAll(sections)
        }
        return holder.template
    }

    // MARK: Track list templates

    static func playlistList(id: Int, title: String) -> CPListTemplate {
        let holder = CarPlayListState(title: title, sections: [
            CPListSection(items: [loadingItem()], header: nil, sectionIndexTitle: nil),
        ])
        func load() {
            Task { @MainActor in
                do {
                    let response = try await NeteaseAPI.playlistDetail(id: id)
                    var tracks = response.playlist.tracks
                    let remaining = response.playlist.trackIds.map(\.id).dropFirst(tracks.count)
                    for chunk in stride(from: 0, to: remaining.count, by: 500)
                        .map({ Array(remaining.dropFirst($0).prefix(500)) }) {
                        guard let resp = try? await NeteaseAPI.songDetails(ids: chunk) else { break }
                        tracks += resp.songs
                    }
                    holder.update(items(for: tracks, source: .playlist(id)), at: 0)
                } catch {
                    holder.update([errorItem(error, retry: load)], at: 0)
                }
            }
        }
        load()
        return holder.template
    }

    static func dailyList() -> CPListTemplate {
        let holder = CarPlayListState(title: String(localized: "每日推荐"), sections: [
            CPListSection(items: [loadingItem()], header: nil, sectionIndexTitle: nil),
        ])
        func load() {
            Task { @MainActor in
                do {
                    let tracks = try await NeteaseAPI.dailyRecommendSongs()
                    holder.update(items(for: tracks, source: .daily), at: 0)
                } catch {
                    holder.update([errorItem(error, retry: load)], at: 0)
                }
            }
        }
        load()
        return holder.template
    }

    static func recentList() -> CPListTemplate {
        let holder = CarPlayListState(title: String(localized: "最近播放"), sections: [
            CPListSection(items: [loadingItem()], header: nil, sectionIndexTitle: nil),
        ])
        func load() {
            Task { @MainActor in
                guard let uid = AccountStore.shared.profile?.userId else {
                    holder.updateAll([CPListSection(items: [loginItem()], header: nil, sectionIndexTitle: nil)])
                    return
                }
                do {
                    let records = try await NeteaseAPI.playRecords(uid: uid, week: false)
                    holder.update(items(for: records.map(\.song), source: .none), at: 0)
                } catch {
                    holder.update([errorItem(error, retry: load)], at: 0)
                }
            }
        }
        load()
        return holder.template
    }

    // MARK: Items

    private static func items(for tracks: [Track], source: PlaySource) -> [CPListItem] {
        let batch = CarPlayTrackBatch(tracks: tracks, source: source)
        var items: [CPListItem] = []
        if !tracks.isEmpty {
            items.append(playAllItem(batch: batch))
        }
        items.append(contentsOf: tracks.map { trackItem($0, batch: batch) })
        return items
    }

    private static func playAllItem(batch: CarPlayTrackBatch) -> CPListItem {
        let item = CPListItem(
            text: String(localized: "播放全部"),
            detailText: String(localized: "\(batch.tracks.count) 首"),
            image: UIImage(systemName: "play.fill"),
            accessoryImage: nil, accessoryType: .none
        )
        item.handler = { _, completion in
            MainActor.assumeIsolated {
                PlayerService.shared.play(tracks: batch.tracks, source: batch.source)
            }
            completion()
        }
        return item
    }

    private static func trackItem(_ track: Track, batch: CarPlayTrackBatch) -> CPListItem {
        let item = CPListItem(
            text: track.name,
            detailText: track.artistNames,
            image: nil, accessoryImage: nil, accessoryType: .none
        )
        item.handler = { _, completion in
            MainActor.assumeIsolated {
                PlayerService.shared.play(tracks: batch.tracks, source: batch.source, startAt: track)
            }
            completion()
        }
        loadArtwork(for: item, url: track.album.picUrl?.resizedImageURL(256))
        return item
    }

    private static func playlistItem(_ playlist: PlaylistSummary) -> CPListItem {
        let item = CPListItem(
            text: playlist.name,
            detailText: playlist.trackCount > 0 ? String(localized: "\(playlist.trackCount) 首") : nil,
            image: nil, accessoryImage: nil, accessoryType: .none
        )
        item.handler = { _, completion in
            MainActor.assumeIsolated {
                CarPlayBridge.interfaceController?.pushTemplate(
                    playlistList(id: playlist.id, title: playlist.name),
                    animated: true, completion: nil
                )
            }
            completion()
        }
        loadArtwork(for: item, url: playlist.coverURL?.resizedImageURL(256))
        return item
    }

    private static func toplistItem(_ list: ToplistItem) -> CPListItem {
        let item = CPListItem(
            text: list.name,
            detailText: list.updateFrequency,
            image: nil, accessoryImage: nil, accessoryType: .none
        )
        item.handler = { _, completion in
            MainActor.assumeIsolated {
                CarPlayBridge.interfaceController?.pushTemplate(
                    playlistList(id: list.id, title: list.name),
                    animated: true, completion: nil
                )
            }
            completion()
        }
        loadArtwork(for: item, url: list.coverImgUrl?.resizedImageURL(256))
        return item
    }

    private static func dailyItem() -> CPListItem {
        let item = CPListItem(
            text: String(localized: "每日推荐"),
            detailText: String(localized: "根据你的口味 · 每天 6:00 更新"),
            image: UIImage(systemName: "calendar"),
            accessoryImage: nil, accessoryType: .none
        )
        item.handler = { _, completion in
            MainActor.assumeIsolated {
                CarPlayBridge.interfaceController?.pushTemplate(
                    dailyList(), animated: true, completion: nil
                )
            }
            completion()
        }
        return item
    }

    private static func fmItem() -> CPListItem {
        let item = CPListItem(
            text: String(localized: "私人漫游"),
            detailText: String(localized: "按你的口味随机播放"),
            image: UIImage(systemName: "wave.3.right"),
            accessoryImage: nil, accessoryType: .none
        )
        item.handler = { _, completion in
            MainActor.assumeIsolated {
                if AccountStore.shared.isLoggedIn {
                    PlayerService.shared.startFM()
                } else {
                    CarPlayBridge.interfaceController?.pushTemplate(
                        loginAlert(), animated: true, completion: nil
                    )
                }
            }
            completion()
        }
        return item
    }

    private static func recentItem() -> CPListItem {
        let item = CPListItem(
            text: String(localized: "最近播放"),
            detailText: nil,
            image: UIImage(systemName: "clock.fill"),
            accessoryImage: nil, accessoryType: .none
        )
        item.handler = { _, completion in
            MainActor.assumeIsolated {
                CarPlayBridge.interfaceController?.pushTemplate(
                    recentList(), animated: true, completion: nil
                )
            }
            completion()
        }
        return item
    }

    private static func libraryRootItem() -> CPListItem {
        let item = CPListItem(
            text: String(localized: "我的音乐"),
            detailText: String(localized: "喜欢的音乐与歌单"),
            image: UIImage(systemName: "music.note.list"),
            accessoryImage: nil, accessoryType: .disclosureIndicator
        )
        item.handler = { _, completion in
            MainActor.assumeIsolated {
                CarPlayBridge.interfaceController?.pushTemplate(
                    library(), animated: true, completion: nil
                )
            }
            completion()
        }
        return item
    }

    private static func loginItem() -> CPListItem {
        let item = CPListItem(
            text: String(localized: "登录 Kumone"),
            detailText: String(localized: "在 iPhone 上扫码登录后，这里会显示你的歌单"),
            image: UIImage(systemName: "person.crop.circle.badge.plus"),
            accessoryImage: nil, accessoryType: .none
        )
        item.handler = { _, completion in
            MainActor.assumeIsolated {
                CarPlayBridge.interfaceController?.pushTemplate(
                    loginAlert(), animated: true, completion: nil
                )
            }
            completion()
        }
        return item
    }

    private static func loginAlert() -> CPAlertTemplate {
        CPAlertTemplate(
            titleVariants: [String(localized: "请先在 iPhone 上打开 Kumone 登录")],
            actions: [CPAlertAction(title: String(localized: "知道了"), style: .default, handler: { _ in })]
        )
    }

    private static func loadingItem() -> CPListItem {
        CPListItem(
            text: String(localized: "正在加载…"),
            detailText: nil,
            image: nil, accessoryImage: nil, accessoryType: .none
        )
    }

    private static func errorItem(_ error: Error, retry: @escaping () -> Void) -> CPListItem {
        let item = CPListItem(
            text: String(localized: "加载失败，点按重试"),
            detailText: error.localizedDescription,
            image: UIImage(systemName: "exclamationmark.triangle"),
            accessoryImage: nil, accessoryType: .none
        )
        item.handler = { _, completion in
            MainActor.assumeIsolated { retry() }
            completion()
        }
        return item
    }

    private static func loadArtwork(for item: CPListItem, url: URL?) {
        guard let url else { return }
        Task { @MainActor in
            if let image = await ImageCache.shared.image(for: url) {
                item.setImage(image)
            }
        }
    }
}
#endif
