import Cocoa

let LinkKeyKillLauncherNotification = Notification.Name("LinkKeyKillLauncherNotification")

@NSApplicationMain
class AutoLauncherAppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification)
    {

        let appIdentifier = "com.linkkey.app"

        let runningApps = NSWorkspace.shared.runningApplications
        let appIsRunning = !runningApps.filter { $0.bundleIdentifier == appIdentifier }.isEmpty

        if (appIsRunning == false) {
            // watch for kill notifications from the main app
            DistributedNotificationCenter.default().addObserver(self, selector: #selector(self.terminate), name: LinkKeyKillLauncherNotification, object: appIdentifier)

            // build the url to the main app
            var bundleURL = Bundle.main.bundleURL
            bundleURL.deleteLastPathComponent()
            bundleURL.deleteLastPathComponent()
            bundleURL.deleteLastPathComponent()
            bundleURL.deleteLastPathComponent()

            // launch the main application
            do {
                try NSWorkspace.shared.launchApplication(at: bundleURL, options: [], configuration: [:])
            } catch {
                NSLog("LinkKeyLauncher: Error launching LinkKey. \(error)")
                self.terminate()
            }
        } else {
            // the main app is already running
            self.terminate()
        }
    }

    @objc func terminate()
    {
        NSApp.terminate(nil)
    }

}
