import UIKit

class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    private let bleService = IosBleProximityService()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        // During debug previews, mock connected state so the Disconnect overlay does not block the UI.
        #if DEBUG
        bleService.connectionState = .connectedUnlocked
        #endif
        window?.rootViewController = RootViewController(bleService: bleService)
        window?.makeKeyAndVisible()
        return true
    }
}
