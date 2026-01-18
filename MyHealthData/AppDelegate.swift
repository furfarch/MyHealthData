import Foundation
import UIKit

/// Small store to hold a pending share URL received before the SwiftUI scene is ready.
final class PendingShareStore {
    static let shared = PendingShareStore()
    private init() {}

    private let queue = DispatchQueue(label: "PendingShareStore")
    private var _pendingURL: URL?

    var pendingURL: URL? {
        get { queue.sync { _pendingURL } }
        set { queue.sync { _pendingURL = newValue } }
    }

    func consume() -> URL? {
        return queue.sync { () -> URL? in
            let u = _pendingURL
            _pendingURL = nil
            return u
        }
    }
}

// Scene delegate to handle modern URL / userActivity delivery (iOS 13+ scenes)
@objc
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for context in URLContexts {
            PendingShareStore.shared.pendingURL = context.url
        }
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        if let url = userActivity.webpageURL {
            PendingShareStore.shared.pendingURL = url
        }
    }
}

@objc
class AppDelegate: UIResponder, UIApplicationDelegate {
    // Provide a scene configuration that uses `SceneDelegate` as the scene's delegate class.
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }

    // Fallback acceptance for older code paths (optional). Keep minimal.
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        if let url = userActivity.webpageURL {
            PendingShareStore.shared.pendingURL = url
            return true
        }
        return false
    }
}
