//
//  AppStateManager.swift
//  CopyThat
//
//  Created by Drew Pomerleau on 4/25/22.
//

import Foundation
import ServiceManagement
import ApplicationServices

enum FullDiskAccessStatus {
    case authorized, denied, unknown
}

enum MessagingPlatform: String {
    case iMessage = "imessage"
    case googleMessages = "googlemessages"
}

enum NotificationPosition: Int {
    case leftEdgeTop, leftEdgeBottom, rightEdgeTop, rightEdgeBottom
    
    static let defaultValue: NotificationPosition = .leftEdgeTop
    
    static let all: [NotificationPosition] = [.leftEdgeTop, .leftEdgeBottom, .rightEdgeTop, .rightEdgeBottom]
    
    var name: String {
        switch self {
        case .leftEdgeTop:
            return "Left Edge, Top"
        case .leftEdgeBottom:
            return "Left Edge, Bottom"
        case .rightEdgeTop:
            return "Right Edge, Top"
        case .rightEdgeBottom:
            return "Right Edge, Bottom"
        }
    }
}

class AppStateManager {
    static let shared = AppStateManager()
    
    private init() {}
    
    private struct Constants {
        // Helper Application Bundle Identifier
        static let autoLauncherBundleID = "com.copythat.app.boden.AutoLauncher"
        
        static let autoLauncherPrefKey = "com.copythat.app.shouldAutoLaunch"
        static let globalShortcutEnabledKey = "com.copythat.app.globalShortcutEnabled"
        static let notificationPositionKey = "com.copythat.app.notificationPosition"
        static let restoreContentsDelayTimeKey = "com.copythat.app.restoreContentsDelayTime"
        static let hasSetupKey = "com.copythat.app.hasSetup"
        static let autoPasteEnabledKey = "com.copythat.app.autoPasteEnabled"
        static let showNotificationOverlayKey = "com.copythat.app.showNotificationOverlay"
        static let useNativeNotificationsKey = "com.copythat.app.useNativeNotifications"
        static let markAsReadEnabledKey = "com.copythat.app.markAsReadEnabled"
        static let debugLoggingEnabledKey = "com.copythat.app.debugLoggingEnabled"
        static let messagingPlatformKey = "com.copythat.app.messagingPlatform"
        static let googleMessagesAppInstalledKey = "com.copythat.app.googleMessagesAppInstalled"
        static let currentOnboardingStepKey = "com.copythat.app.currentOnboardingStep"
    }
    
    func hasFullDiscAccess() -> FullDiskAccessStatus {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let messagesPath = homeDirectory.appendingPathComponent("Library/Messages/chat.db").path
        
        let fileExists = FileManager.default.fileExists(atPath: messagesPath)
        let fileURL = URL(fileURLWithPath: messagesPath)
        
        // Try to read a tiny bit of the file to verify access
        var canRead = false
        if let fileHandle = try? FileHandle(forReadingFrom: fileURL) {
            if (try? fileHandle.read(upToCount: 1)) != nil {
                canRead = true
            }
            try? fileHandle.close()
        }
        
        NSLog("[CopyThat] Checking FDA at: \(messagesPath)")
        NSLog("[CopyThat] File exists: \(fileExists), Can read: \(canRead)")

        if canRead {
            return .authorized
        } else if fileExists {
            return .denied
        }
        
        return .unknown
    }
    
    func hasAccessibilityPermission() -> Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: false]
        let status = AXIsProcessTrustedWithOptions(options)
        NSLog("[CopyThat] Checking Accessibility: \(status)")
        return status
    }

    var hasSetup: Bool {
        get {
            return UserDefaults.standard.bool(forKey: Constants.hasSetupKey)
        }
        set(newValue) {
            UserDefaults.standard.set(newValue, forKey: Constants.hasSetupKey)
        }
    }
    
    var shouldLaunchOnLogin: Bool {
        get {
            return UserDefaults.standard.bool(forKey: Constants.autoLauncherPrefKey)
        }
        set(newValue) {
            UserDefaults.standard.set(newValue, forKey: Constants.autoLauncherPrefKey)
            SMLoginItemSetEnabled(Constants.autoLauncherBundleID as CFString, newValue)
        }
    }
    
    var globalShortcutEnabled: Bool {
        get {
            return UserDefaults.standard.bool(forKey: Constants.globalShortcutEnabledKey)
        }
        set(newValue) {
            UserDefaults.standard.set(newValue, forKey: Constants.globalShortcutEnabledKey)
        }
    }
    
    var autoPasteEnabled: Bool {
        get {
            return UserDefaults.standard.bool(forKey: Constants.autoPasteEnabledKey)
        }
        set(newValue) {
            UserDefaults.standard.set(newValue, forKey: Constants.autoPasteEnabledKey)
        }
    }

    var showNotificationOverlay: Bool {
        get {
            // Default to true (show overlay) if not set
            if UserDefaults.standard.object(forKey: Constants.showNotificationOverlayKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Constants.showNotificationOverlayKey)
        }
        set(newValue) {
            UserDefaults.standard.set(newValue, forKey: Constants.showNotificationOverlayKey)
        }
    }

    var useNativeNotifications: Bool {
        get {
            // Default to false (use custom overlay)
            return UserDefaults.standard.bool(forKey: Constants.useNativeNotificationsKey)
        }
        set(newValue) {
            UserDefaults.standard.set(newValue, forKey: Constants.useNativeNotificationsKey)
        }
    }

    var markAsReadEnabled: Bool {
        get {
            // Default to false (don't mark as read)
            return UserDefaults.standard.bool(forKey: Constants.markAsReadEnabledKey)
        }
        set(newValue) {
            UserDefaults.standard.set(newValue, forKey: Constants.markAsReadEnabledKey)
        }
    }

    var notificationPosition: NotificationPosition {
        get {
            if let storedRawValue = UserDefaults.standard.value(forKey: Constants.notificationPositionKey) as? Int {
                return NotificationPosition(rawValue: storedRawValue) ?? NotificationPosition.defaultValue
            } else {
                return NotificationPosition.defaultValue
            }
        }
        set(newValue) {
            UserDefaults.standard.set(newValue.rawValue, forKey: Constants.notificationPositionKey)
        }
    }
    
    // Set to 0 to disable
    var restoreContentsDelayTime: Int {
        get {
            let value = UserDefaults.standard.value(forKey: Constants.restoreContentsDelayTimeKey)
            if (value == nil) {
                // Default value
                return 5;
            } else {
                return value as! Int
            }
        }
        set(newValue) {
            UserDefaults.standard.set(newValue, forKey: Constants.restoreContentsDelayTimeKey)
        }
    }
    
    var restoreContentsEnabled: Bool {
        get {
            return self.restoreContentsDelayTime > 0
        }
    }

    var debugLoggingEnabled: Bool {
        get {
            // Default to false (don't log)
            return UserDefaults.standard.bool(forKey: Constants.debugLoggingEnabledKey)
        }
        set(newValue) {
            UserDefaults.standard.set(newValue, forKey: Constants.debugLoggingEnabledKey)
            if newValue {
                DebugLogger.shared.log("Debug logging enabled", category: "SYSTEM")
            }
        }
    }

    var messagingPlatform: MessagingPlatform {
        get {
            if let rawValue = UserDefaults.standard.string(forKey: Constants.messagingPlatformKey),
               let platform = MessagingPlatform(rawValue: rawValue) {
                return platform
            }
            return .iMessage // Default to iMessage
        }
        set(newValue) {
            UserDefaults.standard.set(newValue.rawValue, forKey: Constants.messagingPlatformKey)
        }
    }

    var googleMessagesAppInstalled: Bool {
        get {
            return UserDefaults.standard.bool(forKey: Constants.googleMessagesAppInstalledKey)
        }
        set(newValue) {
            UserDefaults.standard.set(newValue, forKey: Constants.googleMessagesAppInstalledKey)
        }
    }

    var currentOnboardingStep: String? {
        get {
            return UserDefaults.standard.string(forKey: Constants.currentOnboardingStepKey)
        }
        set(newValue) {
            UserDefaults.standard.set(newValue, forKey: Constants.currentOnboardingStepKey)
        }
    }

    func isGoogleMessagesAppInstalled() -> Bool {
        let appPath = "/Applications/Google Messages.app"
        return FileManager.default.fileExists(atPath: appPath)
    }
}
