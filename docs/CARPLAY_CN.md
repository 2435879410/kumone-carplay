# Kumone CarPlay 版使用与构建说明

本仓库是 [missuo/kumone](https://github.com/missuo/kumone)（v0.2.8）的衍生版本，在原 iOS 客户端基础上**新增 CarPlay 支持**。协议延续 LGPL-3.0-only，仅供个人学习与侧载使用。

## 新增的 CarPlay 功能

- 车机主屏两个标签页：**推荐** 与 **我的音乐**
- 推荐页：每日推荐、私人漫游（FM）、最近播放、推荐歌单、排行榜
- 我的音乐：我喜欢的音乐、创建的歌单、收藏的歌单（未登录时提示到 iPhone 上登录）
- 点歌单进入歌曲列表：顶部「播放全部」，点任意歌曲即播放（含 VIP/灰色歌曲解锁，与手机端同一引擎）
- **正在播放屏**：封面、歌名、歌手、进度条、播放/暂停、上一首/下一首、红心、随机/循环，均由系统的 MPNowPlayingInfoCenter / MPRemoteCommandCenter 驱动，与锁屏、控制中心共用
- CarPlay 与 iPhone 端共享登录态、歌单与播放队列（同一进程内的 PlayerService / AccountStore 单例）

## 改动清单

| 文件 | 改动 |
| --- | --- |
| `Sources/Kumone/Features/CarPlay/KumoneCarPlay.swift` | 新增：CarPlay 场景代理 `KumoneCarPlaySceneDelegate` + 模板树构建（`#if os(iOS)`，不影响 macOS） |
| `ios/Config/Info.plist` | 注册 `CPTemplateApplicationSceneSessionRoleApplication` 场景，delegate 指向 `KumoneCore.KumoneCarPlaySceneDelegate` |
| `ios/Config/KumoneIOS.entitlements` | 新增 `com.apple.developer.playable-content`（CarPlay 音频应用权限） |
| `Sources/Kumone/Core/Player/NowPlayingManager.swift` | 新增随机/循环遥控命令（惠及 CarPlay 正在播放屏与锁屏） |
| `.github/workflows/ios-ipa.yml` | 新增 CI：推送到 main 即构建无签名 IPA |
| `CarPlay.entitlements` | 独立的权限文件，供签名工具注入 |

## 一、获得 IPA

### 方式 A：GitHub Actions（推荐，本仓库默认）

推送到 `main` 分支（或手动 `workflow_dispatch`）会自动在 macos-26 runner 上构建，产物为 **无签名** 的 `Kumone-iOS-0.3.0-carplay-unsigned.ipa`。构建完成后在 Actions 页面的 Artifacts 中下载。

### 方式 B：本机构建（需 Xcode 26+）

```bash
cd ios
xcodegen generate   # 仅当修改过 project.yml 时需要
xcodebuild -workspace KumoneIOS.xcworkspace -scheme KumoneIOS \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  MARKETING_VERSION=0.3.0-carplay CURRENT_PROJECT_VERSION=1 build
mkdir -p Payload
cp -R build/Build/Products/Release-iphoneos/KumoneIOS.app Payload/
zip -qry Kumone-iOS-0.3.0-carplay-unsigned.ipa Payload
```

## 二、签名安装（关键）

CarPlay 音频应用必须携带 **`com.apple.developer.playable-content`** 权限，否则 iOS 不会让应用出现在车机 CarPlay 主屏上。该权限需要 Apple 审批，普通免费 Apple ID 的个人签名（AltStore / SideStore / Sideloadly）**无法**携带它——那样装出来的 App 手机上能正常用，但车机上不显示。

请在支持自定义 entitlements 的工具上签名：

### TrollStore（巨魔，推荐）

仓库根目录的 `CarPlay.entitlements` 已包含所需权限。用 Mac 上的 `ldid` 先给二进制预签名，再安装：

```bash
brew install ldid   # 一次性
rm -rf unsigned && mkdir unsigned
unzip -q Kumone-iOS-0.3.0-carplay-unsigned.ipa -d unsigned
ldid -SCarPlay.entitlements unsigned/Payload/KumoneIOS.app/KumoneIOS
cd unsigned && zip -qry ../Kumone-iOS-0.3.0-carplay.ipa Payload && cd ..
```

然后把 `Kumone-iOS-0.3.0-carplay.ipa` 传到手机上用 TrollStore 安装（TrollStore 会保留原有 entitlements）。

### ESign（设备端）

ESign 导入 IPA 后，在「签名」设置里导入 `CarPlay.entitlements` 文件，再签名安装。

### 付费开发者账号

在开发者后台为 App ID 开启 **CarPlay Audio App** 能力，用对应的 provisioning profile 正常签名即可。

> 说明：本 App 为网易云音乐非官方客户端，不会上架 App Store；CarPlay 权限在正式渠道需要 Apple 批准，因此只适合个人设备侧载使用。

## 三、连接车机验证

1. 手机与车机通过 USB 或无线 CarPlay 连接；
2. 车机 CarPlay 设置 → 应用列表里确认 **Kumone** 已勾选显示；
3. 首次上车先打开 iPhone 上的 Kumone 完成扫码登录（车机上无法扫码）；
4. 车机上点开 Kumone：推荐页 / 我的音乐均可直接选歌播放，正在播放屏自动出现。

### 模拟器调试（无真车）

- Xcode 中运行 KumoneIOS 到任意 iPhone 模拟器；
- 打开 Simulator，菜单 **I/O → External Displays → CarPlay (736x414)** 即可打开 CarPlay 模拟屏；
- CarPlay 模拟器不校验 playable-content 权限，Debug 构建可直接看到界面。

## 常见问题

- **车机上找不到 Kumone？** 九成是签名时没有注入 `com.apple.developer.playable-content`，请按第二节重新签名安装；另外确认车机 CarPlay 设置里允许显示该应用。
- **CarPlay 里点歌没声音？** 手机端确认 App 已登录且能正常播放；CarPlay 与手机共用同一个播放引擎。
- **覆盖安装会不会丢登录？** 本 IPA 与原版 IPA 使用相同 bundle id（`sb.moe.kumone`），用同一工具覆盖安装会保留登录状态与设置。
- **为什么不上架 / 不进 TestFlight？** 网易云非官方客户端 + CarPlay 权限审批，均不符合 Apple 政策，仅限个人学习侧载。

## 后续方向（头脑风暴分支）

- iOS 26 基于 UIWindow 的新 CarPlay API（CarPlay on iPhone）适配；
- CarPlay 歌词/队列的合规呈现方案；
- 车机场景的语音搜索（CPVoiceControlTemplate，需 SiriKit 权限）。
