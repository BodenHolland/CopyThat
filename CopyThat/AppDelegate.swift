import Cocoa
import Combine
import SwiftUI
import ServiceManagement
import HotKey
import ApplicationServices
import UserNotifications

class OverlayWindow: NSWindow {
    init(line1: String?, line2: String?, position: NotificationPosition = .defaultValue) {
        let position = AppStateManager.shared.notificationPosition
        let windowSize = UIConstants.codePopupWindowSize
        let margin = UIConstants.codePopupMargin
        var windowRect: NSRect
        let mainScreenRect = NSScreen.main?.visibleFrame ?? NSRect()
        
        switch position {
        case .leftEdgeTop:
            windowRect = NSRect(x: margin, y: mainScreenRect.maxY - margin - windowSize.height, width: windowSize.width, height: windowSize.height)
        case .leftEdgeBottom:
            windowRect = NSRect(x: margin, y: margin, width: windowSize.width, height: windowSize.height)
        case .rightEdgeTop:
            windowRect = NSRect(x: mainScreenRect.maxX - margin - windowSize.width, y: mainScreenRect.maxY - margin - windowSize.height, width: windowSize.width, height: windowSize.height)
        case .rightEdgeBottom:
            windowRect = NSRect(x: mainScreenRect.maxX - margin - windowSize.width, y: margin, width: windowSize.width, height: windowSize.height)
        }
        
        super.init(contentRect: windowRect, styleMask: [.closable, .fullSizeContentView, .borderless], backing: .buffered, defer: false)

        makeKeyAndOrderFront(nil)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        contentView = NSHostingView(rootView: OverlayView(line1: line1, line2: line2))
        styleMask.insert(NSWindow.StyleMask.borderless)
    
        Timer.scheduledTimer(withTimeInterval: UIConstants.codePopupDuration, repeats: false) { [weak self] _ in
            self?.close()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {

    var messageManager: MessageManager?
    var googleMessagesManager: GoogleMessagesManager?
    private var permissionsService = PermissionsService()

    var statusBarItem: NSStatusItem!

    private var onboardingWindow: NSWindow?
    private var overlayWindow: OverlayWindow?

    var cancellable: Set<AnyCancellable> = []
    
    var mostRecentMessages: [ParsedMessage] = []
    var lastNotificationMessage: Message? = nil
    var shouldShowNotificationOverlay = false
    var originalClipboardContents: String? = nil
    
    var hotKey: HotKey?
    
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        setupStatusBar()
        
        let hasFDA = AppStateManager.shared.hasFullDiscAccess() == .authorized
        let hasAccess = AppStateManager.shared.hasAccessibilityPermission()
        
        NSLog("[CopyThat] App Launched. hasSetup: \(AppStateManager.shared.hasSetup), FDA: \(hasFDA), Access: \(hasAccess)")

        if !AppStateManager.shared.hasSetup {
            NSLog("[CopyThat] Logic: !hasSetup -> Opening Onboarding")
            NSApp.setActivationPolicy(.regular) // MUST set this before showing window
            AppStateManager.shared.shouldLaunchOnLogin = true
            AppStateManager.shared.globalShortcutEnabled = true
            openOnboardingWindow()
        } else if AppStateManager.shared.messagingPlatform == .iMessage {
            if !hasFDA || !hasAccess {
                NSLog("[CopyThat] Logic: iMessage + Missing Permissions -> Opening Onboarding")
                NSApp.setActivationPolicy(.regular) // MUST set this before showing window
                openOnboardingWindow()
            } else {
                NSLog("[CopyThat] Logic: iMessage + All Permissions -> Running as accessory")
                refreshActivationPolicy()
            }
        } else {
            refreshActivationPolicy()
        }
        
        NSApp.activate(ignoringOtherApps: true)
    }

    func setupStatusBar() {
        let statusBar = NSStatusBar.system
        statusBarItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        
        if let icon = NSImage(named: "TrayIcon") {
            icon.isTemplate = true
            icon.size = NSSize(width: 18, height: 18)
            statusBarItem.button?.image = icon
        } else {
            let fallbackIcon = NSImage(systemSymbolName: "key.fill", accessibilityDescription: "CopyThat")
            fallbackIcon?.isTemplate = true
            statusBarItem.button?.image = fallbackIcon
        }
        
        statusBarItem.isVisible = true
        statusBarItem.button?.title = "CopyThat"
        
        if AppStateManager.shared.globalShortcutEnabled {
            setupGlobalKeyShortcut()
        }

        initMessageManager()
        setupKeyboardListener()
        setupNotifications()
        refreshMenu()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NSLog("[CopyThat] Application reopened. flag: \(flag)")
        // Bring the app to the front
        NSApp.activate(ignoringOtherApps: true)
        if !flag {
            // If no windows are visible, open the onboarding window or show status
            if !AppStateManager.shared.hasSetup ||
               (AppStateManager.shared.messagingPlatform == .iMessage &&
                (AppStateManager.shared.hasFullDiscAccess() != .authorized || !AppStateManager.shared.hasAccessibilityPermission())) {
                openOnboardingWindow()
            } else {
                // If setup, just show the status bar menu
                statusBarItem.button?.performClick(nil)
            }
        }
        return true
    }

    func setupNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        // Request notification permissions
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Error requesting notification permission: \(error)")
            }
        }
    }

    func sendNativeNotification(code: String, service: String?) {
        let content = UNMutableNotificationContent()
        content.title = "2FA Code Copied"
        content.body = "\(code)\(service != nil ? " - \(service!)" : "")"
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error sending notification: \(error)")
            }
        }
    }

    // UNUserNotificationCenterDelegate - Show notifications even when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func initMessageManager() {
        // Using SimpleOTPParser - no config needed, uses keyword-based detection
        let otpParser = SimpleOTPParser()

        switch AppStateManager.shared.messagingPlatform {
        case .iMessage:
            // Stop Google Messages if running
            googleMessagesManager?.stopListening()
            googleMessagesManager = nil

            messageManager = MessageManager(withOTPParser: otpParser)
            startListeningForMessages()

        case .googleMessages:
            // Stop iMessage if running
            messageManager?.stopListening()
            messageManager = nil

            googleMessagesManager = GoogleMessagesManager(withOTPParser: otpParser)
            startListeningForGoogleMessages()
        }
    }
    
    func startListeningForMessages() {
        messageManager?.$messages.sink { [weak self] messages in
            guard let weakSelf = self else { return }
            if let newestMessage = messages.last, newestMessage.0 != weakSelf.lastNotificationMessage && weakSelf.shouldShowNotificationOverlay {
                weakSelf.showOverlayForMessage(newestMessage)
            }

            weakSelf.mostRecentMessages = messages.suffix(3)
            weakSelf.refreshMenu()

            weakSelf.shouldShowNotificationOverlay = true
        }.store(in: &cancellable)
        messageManager?.startListening()
    }

    func startListeningForGoogleMessages() {
        googleMessagesManager?.$messages.sink { [weak self] messages in
            guard let weakSelf = self else { return }
            if let newestMessage = messages.last, newestMessage.0 != weakSelf.lastNotificationMessage && weakSelf.shouldShowNotificationOverlay {
                weakSelf.showOverlayForMessage(newestMessage)
            }

            weakSelf.mostRecentMessages = messages.suffix(3)
            weakSelf.refreshMenu()

            weakSelf.shouldShowNotificationOverlay = true
        }.store(in: &cancellable)
        googleMessagesManager?.startListening()
    }

    func showOverlayForMessage(_ message: ParsedMessage) {
        if let overlayWindow = overlayWindow {
            overlayWindow.close()
            self.overlayWindow = nil
        }

        lastNotificationMessage = message.0

        // Always copy to clipboard regardless of overlay setting
        self.originalClipboardContents = message.1.copyToClipboard()

        // Mark message as read if enabled
        messageManager?.markMessageAsRead(guid: message.0.guid)

        if AppStateManager.shared.autoPasteEnabled && AppStateManager.shared.hasAccessibilityPermission() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                let source = CGEventSource(stateID: .combinedSessionState)
                let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
                let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
                keyDown?.flags = .maskCommand
                keyUp?.flags = .maskCommand
                keyDown?.post(tap: .cgAnnotatedSessionEventTap)
                keyUp?.post(tap: .cgAnnotatedSessionEventTap)
            }
        }

        restoreClipboardContents(withDelay: AppStateManager.shared.restoreContentsDelayTime)

        // Use native notifications or custom overlay based on setting
        if AppStateManager.shared.useNativeNotifications {
            sendNativeNotification(code: message.1.code, service: message.1.service)
        } else if AppStateManager.shared.showNotificationOverlay {
            let window = OverlayWindow(line1: message.1.code, line2: "Copied to Clipboard")
            window.makeKeyAndOrderFront(nil)
            window.level = NSWindow.Level.statusBar
            overlayWindow = window
        }
    }

    func refreshMenu() {
        statusBarItem.menu = createMenuForMessages()
    }
    
    func createOnboardingWindow() -> NSWindow? {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Setup CopyThat"
        window.contentView = NSHostingView(rootView: OnboardingView())
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("OnboardingWindow")
        window.minSize = NSSize(width: 600, height: 500)
        window.center()
        return window
    }
    
    func createMenuForMessages() -> NSMenu {
        let statusBarMenu = NSMenu()

        // Show status based on current platform
        let statusText: String
        switch AppStateManager.shared.messagingPlatform {
        case .iMessage:
            statusText = AppStateManager.shared.hasFullDiscAccess() == .authorized ? "🟢 Connected to iMessage" : "⚠️ Setup CopyThat"
        case .googleMessages:
            statusText = AppStateManager.shared.isGoogleMessagesAppInstalled() ? "🟢 Connected to Google Messages" : "⚠️ Setup Google Messages"
        }

        statusBarMenu.addItem(
            withTitle: statusText,
            action: #selector(AppDelegate.onPressSetup),
            keyEquivalent: "")

        statusBarMenu.addItem(
            withTitle: "🚀 Send Test Notification",
            action: #selector(AppDelegate.onPressTestNotification),
            keyEquivalent: "")

        statusBarMenu.addItem(NSMenuItem.separator())

        statusBarMenu.addItem(withTitle: "Recent", action: nil, keyEquivalent: "")
        mostRecentMessages.enumerated().forEach { (index, row) in
            let (_, parsedOtp) = row
            let menuItem = NSMenuItem(title: "\(parsedOtp.code) - \(parsedOtp.service ?? "Unknown")", action: #selector(AppDelegate.onPressCode), keyEquivalent: "")
            menuItem.tag = index
            statusBarMenu.addItem(menuItem)
        }
        
        statusBarMenu.addItem(NSMenuItem.separator())

        // Only show Resync for iMessage (Google Messages doesn't have a database to resync from)
        if AppStateManager.shared.messagingPlatform == .iMessage {
            let resyncItem = NSMenuItem(title: "Resync", action: #selector(AppDelegate.resync), keyEquivalent: "")
            resyncItem.toolTip = "Sometimes iMessage likes to sleep on the job. If CopyThat ever misses a message, use this option to sync recent messages and copy the latest code to your clipboard"
            statusBarMenu.addItem(resyncItem)
        }
        
        let settingsMenu = NSMenu()

        // Native Notifications toggle
        let useNativeNotificationsItem = NSMenuItem(title: "Use Native Notifications", action: #selector(AppDelegate.onPressUseNativeNotifications), keyEquivalent: "")
        useNativeNotificationsItem.toolTip = "Use macOS native notifications instead of custom overlay (follows Do Not Disturb settings)"
        useNativeNotificationsItem.state = AppStateManager.shared.useNativeNotifications ? .on : .off
        settingsMenu.addItem(useNativeNotificationsItem)

        // Only show custom overlay settings if native notifications are disabled
        if !AppStateManager.shared.useNativeNotifications {
            let notificationPositionMenu = NSMenu()
            let positions = NotificationPosition.all
            positions.forEach { position in
                let item = NSMenuItem(title: position.name, action: #selector(AppDelegate.onPressNotificationPosition), keyEquivalent: "")
                item.representedObject = position
                item.state = AppStateManager.shared.notificationPosition == position ? .on : .off
                notificationPositionMenu.addItem(item)
            }

            let notificationPositionItem = NSMenuItem(title: "Notification Position", action: nil, keyEquivalent: "")
            notificationPositionItem.toolTip = "Select where notifications will appear on the screen"
            notificationPositionItem.state = .off
            notificationPositionItem.submenu = notificationPositionMenu
            settingsMenu.addItem(notificationPositionItem)

            let showOverlayItem = NSMenuItem(title: "Show Notification Overlay", action: #selector(AppDelegate.onPressShowOverlay), keyEquivalent: "")
            showOverlayItem.toolTip = "Show a notification overlay when a code is copied (disable for privacy during screen recordings)"
            showOverlayItem.state = AppStateManager.shared.showNotificationOverlay ? .on : .off
            settingsMenu.addItem(showOverlayItem)
        }

        let keyboardShortCutItem = NSMenuItem(title: "Keyboard Shortcuts", action: #selector(AppDelegate.onPressKeyboardShortcuts), keyEquivalent: "")
        keyboardShortCutItem.toolTip = "Disable keyboard shortcuts if CopyThat uses the same keyboard shortcuts as another app"
        keyboardShortCutItem.state = AppStateManager.shared.globalShortcutEnabled ? .on : .off
        settingsMenu.addItem(keyboardShortCutItem)

        let autoPasteItem = NSMenuItem(title: "Auto-Paste Codes", action: #selector(AppDelegate.onPressAutoPaste), keyEquivalent: "")
        autoPasteItem.toolTip = "Automatically paste codes into focused text field (requires accessibility permissions)"
        autoPasteItem.state = AppStateManager.shared.autoPasteEnabled ? .on : .off
        settingsMenu.addItem(autoPasteItem)

        // Only show "Mark as Read" for iMessage (not applicable for Google Messages)
        if AppStateManager.shared.messagingPlatform == .iMessage {
            let markAsReadItem = NSMenuItem(title: "Mark Messages as Read", action: #selector(AppDelegate.onPressMarkAsRead), keyEquivalent: "")
            markAsReadItem.toolTip = "Automatically mark OTP messages as read in iMessage after copying the code"
            markAsReadItem.state = AppStateManager.shared.markAsReadEnabled ? .on : .off
            settingsMenu.addItem(markAsReadItem)
        }

        let restoreContentsMenu = NSMenu()
        let delayTimes = [0, 5, 10, 15, 20]
        delayTimes.forEach { delayTime in
            let item = NSMenuItem(title: "\(String(describing: delayTime)) sec", action: #selector(AppDelegate.onPressRestoreClipboardContents), keyEquivalent: "")
            if (delayTime == 0) {
                item.title = "Disabled"
            }
            item.representedObject = delayTime
            item.state = AppStateManager.shared.restoreContentsDelayTime == delayTime ? .on : .off
            restoreContentsMenu.addItem(item)
        }
        
        let restoreContentsItem = NSMenuItem(title: "Restore Clipboard Contents", action: #selector(AppDelegate.onPressRestoreClipboardContents), keyEquivalent: "")
        restoreContentsItem.toolTip = "Disable restore clipboard contents if you don't want CopyThat to restore your clipboard to what it was before receiving a code"
        restoreContentsItem.state = AppStateManager.shared.restoreContentsEnabled ? .on : .off
        restoreContentsItem.submenu = restoreContentsMenu
        settingsMenu.addItem(restoreContentsItem)

        let autoLaunchItem = NSMenuItem(title: "Open at Login", action: #selector(AppDelegate.onPressAutoLaunch), keyEquivalent: "")
        autoLaunchItem.state = AppStateManager.shared.shouldLaunchOnLogin ? .on : .off
        settingsMenu.addItem(autoLaunchItem)

        let hideMenuBarItem = NSMenuItem(title: "Hide Menu Bar Icon", action: #selector(AppDelegate.onPressHideMenuBar), keyEquivalent: "")
        hideMenuBarItem.toolTip = "Hide the menu bar icon until the app is relaunched"
        settingsMenu.addItem(hideMenuBarItem)

        settingsMenu.addItem(NSMenuItem.separator())

        // Switch Platform option
        let targetPlatformName = AppStateManager.shared.messagingPlatform == .iMessage ? "Google Messages" : "iMessage"
        let switchPlatformItem = NSMenuItem(title: "Switch to \(targetPlatformName)", action: #selector(AppDelegate.onPressSwitchPlatform), keyEquivalent: "")
        switchPlatformItem.toolTip = "Switch to \(targetPlatformName) for verification codes"
        settingsMenu.addItem(switchPlatformItem)

        settingsMenu.addItem(NSMenuItem.separator())

        let debugLoggingItem = NSMenuItem(title: "Debug Logging", action: #selector(AppDelegate.onPressDebugLogging), keyEquivalent: "")
        debugLoggingItem.toolTip = "Enable debug logging to troubleshoot iMessage database issues. Logs are saved to ~/Documents/CopyThat_Debug.log"
        debugLoggingItem.state = AppStateManager.shared.debugLoggingEnabled ? .on : .off
        settingsMenu.addItem(debugLoggingItem)

        if AppStateManager.shared.debugLoggingEnabled {
            let openLogItem = NSMenuItem(title: "Open Debug Log", action: #selector(AppDelegate.onPressOpenDebugLog), keyEquivalent: "")
            openLogItem.toolTip = "Open the debug log file in Finder"
            settingsMenu.addItem(openLogItem)

            let clearLogItem = NSMenuItem(title: "Clear Debug Log", action: #selector(AppDelegate.onPressClearDebugLog), keyEquivalent: "")
            clearLogItem.toolTip = "Clear the debug log file"
            settingsMenu.addItem(clearLogItem)
        }

        let settingsItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        settingsItem.submenu = settingsMenu
        statusBarMenu.addItem(settingsItem)

        // Debug menu (only in Debug builds)
        #if DEBUG
        statusBarMenu.addItem(NSMenuItem.separator())
        let debugMenu = NSMenu()

        let testMessages = [
            // Generic patterns (should work with en.json patterns)
            ("Google", "G-123456 is your Google verification code."),
            ("Apple", "Your Apple ID Code is: 654321. Don't share it with anyone."),
            ("Amazon", "123456 is your Amazon OTP. Do not share it with anyone."),
            ("Generic code:", "Your code: 456789"),
            ("Verification code is", "Your verification code is 789012"),
            ("Security code", "Your security code is: 654321"),
            ("Login code", "Your login code: 123456"),
            ("One-time password", "Your one-time password is 987654"),
            ("Validation code", "Your validation code is 456123"),
            ("Confirmation code", "Your confirmation code: 789456"),
            ("JAILATM (use pattern)", "Truist Alerts: To verify the JAILATM CO transaction on card 0323, use 582270. We won't contact you for this code."),
            ("Link verification", "132637 is your Link verification code."),
            ("Alphanumeric", "ABC123 is your verification code"),
            ("Chase", "From: Chase\nWe'll NEVER call you to ask for this code.\nOne-Time Code:12345678\nOnly use this online. Code expires in 30 min."),
            ("Geico alphanumeric", "GEICO: Your verification code is: ABC123. It expires in 10 minutes."),
            ("Vodafone alphanumeric", "Your code is AB12C."),
            // Chinese patterns
            ("Chinese (Zhihu)", "【知乎】你的验证码是 700185，此验证码用于登录知乎或重置密码。10 分钟内有效。"),
            ("Chinese (JD)", "【京东】验证码：548393，您正在新设备上登录。"),
            // Custom patterns (exceptional cases only)
            ("Custom: DBS Bank", "Please use SGD-123456 within 3 minutes to authorize this transaction."),
            ("Custom: MIGov", "Your passcode is\n1234-567890"),
            ("Custom: pf-bank", "12345678\nValid 5 minutes. Do not share."),
            ("Custom: idCAT Mobil", "@valid.aoc.cat #654321"),
            ("Custom: FNZ Finvesto", "Ihr Bestätigungscode ist: AB3C45"),
            ("Custom: Cater Allen", "OTP to MAKE A NEW PAYMENT of GBP 9.94 to 560027 & 27613445. Call us if this wasn't you. NEVER share this code, not even with Cater Allen staff 699486"),
        ]

        testMessages.forEach { (name, message) in
            let item = NSMenuItem(title: "Test: \(name)", action: #selector(AppDelegate.injectTestMessage), keyEquivalent: "")
            item.representedObject = message
            debugMenu.addItem(item)
        }

        let debugItem = NSMenuItem(title: "🐛 Debug", action: nil, keyEquivalent: "")
        debugItem.submenu = debugMenu
        statusBarMenu.addItem(debugItem)
        #endif

        statusBarMenu.addItem(
            withTitle: "Quit CopyThat",
            action: #selector(AppDelegate.quit),
            keyEquivalent: "")
        return statusBarMenu
    }
    
    func setupKeyboardListener() {
        if (AppStateManager.shared.restoreContentsEnabled) {
            // Only monitor keyDown events (removed systemDefined and appKitDefined for efficiency)
            NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { (event) in
                // If command + V pressed, race restoring the clipboard contents between this listener and the default delay interval
                // Early exit if command key isn't pressed to reduce overhead
                guard event.modifierFlags.contains(.command) else { return }
                if event.keyCode == 9 {
                    self.restoreClipboardContents(withDelay: 5)
                }
            }
        }
    }
    
    func openOnboardingWindow() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            NSLog("[CopyThat] openOnboardingWindow called (async)")
            NSApp.setActivationPolicy(.regular)
            self.refreshActivationPolicy()
            
            if self.onboardingWindow == nil {
                NSLog("[CopyThat] Creating new onboarding window")
                self.onboardingWindow = self.createOnboardingWindow()
                NotificationCenter.default.addObserver(self, selector: #selector(self.onboardingWindowDidClose(_:)), name: NSWindow.willCloseNotification, object: self.onboardingWindow)
            }
            
            self.onboardingWindow?.center()
            self.onboardingWindow?.level = .floating
            self.onboardingWindow?.makeKeyAndOrderFront(nil)
            
            NSApp.activate(ignoringOtherApps: true)
            NSLog("[CopyThat] Window ordered front. Visible: \(self.onboardingWindow?.isVisible ?? false)")
        }
    }

    @objc func onboardingWindowDidClose(_ notification: Notification) {
        NSLog("[CopyThat] Onboarding window closed")
        onboardingWindow = nil // Nil it out so it can be recreated correctly
        refreshActivationPolicy()
    }

    func refreshActivationPolicy() {
        if AppStateManager.shared.hasSetup {
            NSApp.setActivationPolicy(.accessory)
        } else {
            NSApp.setActivationPolicy(.regular)
        }
    }
    
    @objc func resync() {
        shouldShowNotificationOverlay = false
        lastNotificationMessage = nil
        originalClipboardContents = nil

        // Reset the appropriate manager based on platform
        switch AppStateManager.shared.messagingPlatform {
        case .iMessage:
            messageManager?.reset()
        case .googleMessages:
            googleMessagesManager?.reset()
        }
    }

    @objc func onPressSwitchPlatform() {
        // Reset hasSetup to trigger onboarding from platform selection
        AppStateManager.shared.hasSetup = false
        openOnboardingWindow()
    }

    @objc func onPressAutoLaunch() {
        AppStateManager.shared.shouldLaunchOnLogin = !AppStateManager.shared.shouldLaunchOnLogin
        refreshMenu()
    }

    @objc func onPressHideMenuBar() {
        let alert = NSAlert()
        alert.messageText = "Hide Menu Bar Icon?"
        alert.informativeText = "The menu bar icon will be hidden until you quit and relaunch CopyThat. You can quit the app using Activity Monitor or by running 'killall CopyThat' in Terminal."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Hide Icon")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            statusBarItem?.isVisible = false
        }
    }

    @objc func onPressKeyboardShortcuts() {
        AppStateManager.shared.globalShortcutEnabled = !AppStateManager.shared.globalShortcutEnabled
        refreshMenu()
        setupGlobalKeyShortcut()
    }
    
    @objc func onPressRestoreClipboardContents(sender: NSMenuItem) {
        let newDelayTime = sender.representedObject == nil ? 0 : sender.representedObject as! Int;
        AppStateManager.shared.restoreContentsDelayTime = newDelayTime
        refreshMenu()
    }
    
    func setupGlobalKeyShortcut() {
        if AppStateManager.shared.globalShortcutEnabled && hotKey == nil {
            // Setup hot key for ⌥⌘R
            hotKey = HotKey(key: .e, modifiers: [.command, .shift])
            hotKey?.keyDownHandler = { [weak self] in
                self?.resync()
            }
        } else if !AppStateManager.shared.globalShortcutEnabled {
            hotKey = nil
        }
    }
    
    @objc func onPressNotificationPosition(sender: NSMenuItem) {
        if let newNotificationPosition = sender.representedObject as? NotificationPosition {
            AppStateManager.shared.notificationPosition = newNotificationPosition
            refreshMenu()
        }
    }
    
    @objc func onPressAutoPaste() {
        AppStateManager.shared.autoPasteEnabled = !AppStateManager.shared.autoPasteEnabled
        refreshMenu()
    }

    @objc func onPressShowOverlay() {
        AppStateManager.shared.showNotificationOverlay = !AppStateManager.shared.showNotificationOverlay
        refreshMenu()
    }

    @objc func onPressUseNativeNotifications() {
        AppStateManager.shared.useNativeNotifications = !AppStateManager.shared.useNativeNotifications
        refreshMenu()
    }

    @objc func onPressMarkAsRead() {
        AppStateManager.shared.markAsReadEnabled = !AppStateManager.shared.markAsReadEnabled
        refreshMenu()
    }

    @objc func onPressTestNotification() {
        let testMessage = Message(rowId: 0, guid: "test-\(UUID().uuidString)", text: "Your CopyThat test code is 123456", handle: "CopyThat Test", group: nil, fromMe: false)
        let parsed = ParsedOTP(service: "CopyThat Test", code: "123456")
        showOverlayForMessage((testMessage, parsed))
    }

    @objc func onPressDebugLogging() {
        AppStateManager.shared.debugLoggingEnabled = !AppStateManager.shared.debugLoggingEnabled
        refreshMenu()
    }

    @objc func onPressOpenDebugLog() {
        if let logPath = DebugLogger.shared.getLogFilePath() {
            NSWorkspace.shared.selectFile(logPath, inFileViewerRootedAtPath: "")
        }
    }

    @objc func onPressClearDebugLog() {
        DebugLogger.shared.clearLog()
        DebugLogger.shared.log("Debug log cleared by user", category: "SYSTEM")
    }

    @objc func injectTestMessage(_ sender: NSMenuItem) {
        guard let message = sender.representedObject as? String else { return }
        print("🧪 Injecting test message: \(message)")

        // Inject into the appropriate manager based on platform
        switch AppStateManager.shared.messagingPlatform {
        case .iMessage:
            messageManager?.injectTestMessage(message)
        case .googleMessages:
            googleMessagesManager?.injectTestMessage(message)
        }
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }
    
    @objc func onPressSetup() {
        openOnboardingWindow()
    }
    
    @objc func onPressCode(_ sender: Any) {
        guard let index = (sender as? NSMenuItem)?.tag else { return }
        let (_, parsedOtp) = mostRecentMessages[index]
        self.originalClipboardContents = parsedOtp.copyToClipboard()
        restoreClipboardContents(withDelay: AppStateManager.shared.restoreContentsDelayTime)
    }
    
    // Restores clipboard contents after a provided delay in seconds
    // Meant to be called any number of times, each call will race between each other and only
    // restore contents when contents are set
    func restoreClipboardContents(withDelay delaySeconds: Int) {
        let delayTimeInterval = DispatchTimeInterval.seconds(delaySeconds)
        DispatchQueue.main.asyncAfter(deadline: .now() + delayTimeInterval) {
            if (self.originalClipboardContents != nil) {
                NSPasteboard.general.setString(self.originalClipboardContents!, forType: .string)
                self.originalClipboardContents = nil

                // Only show overlay if custom overlay is enabled (not native notifications)
                if !AppStateManager.shared.useNativeNotifications && AppStateManager.shared.showNotificationOverlay {
                    let window = OverlayWindow(line1: "Clipboard Restored", line2: nil)
                    self.overlayWindow = window
                }
            }
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
    
}

