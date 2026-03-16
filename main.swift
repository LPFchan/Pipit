import UIKit

// Modern approach to allow SwiftUI Previews to bypass full app launch
let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"

if isPreview {
    // If running in a SwiftUI preview canvas, just boot an empty shell to avoid crashing on hardware like BLE
    UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(UIViewController.self))
} else {
    // If running the actual app, boot the normal AppDelegate
    UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(AppDelegate.self))
}
