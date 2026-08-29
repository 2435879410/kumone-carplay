import SwiftUI
import KumoneIOSFeature
import CarPlay
import UIKit

/// Keep the CarPlay scene entry point in the application target itself.
/// iOS 15 resolves scene delegates from Info.plist before SwiftUI creates the
/// phone scene, so using the main executable's module removes any ambiguity
/// around resolving a delegate that lives in a statically linked package.
final class KumoneIOSCarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        KumoneCarPlayBootstrap.connect(interfaceController)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController,
        to window: CPWindow
    ) {
        KumoneCarPlayBootstrap.connect(interfaceController)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController
    ) {
        KumoneCarPlayBootstrap.disconnect(interfaceController)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController,
        from window: CPWindow
    ) {
        KumoneCarPlayBootstrap.disconnect(interfaceController)
    }
}

@main
struct KumoneIOSApp: App {
    init() {
        // Register the iOS 15 playable-content data source before CarPlay asks
        // the process for its root browse items.
        KumoneLegacyCarPlay.start()
    }

    var body: some Scene {
        WindowGroup {
            IOSMainWindow()
        }
    }
}
