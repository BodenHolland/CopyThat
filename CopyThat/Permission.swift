import Cocoa

final class PermissionsService {
    // This static method attempts to prompt the user for Accessibility permissions
    static func acquireAccessibilityPrivileges() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true]
        let status = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        // If not granted, also open the System Settings page to help the user find it
        if !status {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
