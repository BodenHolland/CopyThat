//
//  OnboardingView.swift
//  CopyThat
//

import SwiftUI

enum OnboardingStep: String {
    case platformSelection = "platformSelection"
    case iMessagePermissions = "iMessagePermissions"
    case googleMessagesSetup = "googleMessagesSetup"
    case featureOverview = "featureOverview"
}

struct OnboardingView: View {
    @StateObject private var viewModel = OnboardingViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            switch viewModel.currentStep {
            case .platformSelection:
                PlatformSelectionView(
                    selectedPlatform: $viewModel.selectedPlatform,
                    onContinue: {
                        viewModel.proceedFromPlatformSelection()
                    }
                )
            case .iMessagePermissions:
                IMessagePermissionsView(viewModel: viewModel)
            case .googleMessagesSetup:
                GoogleMessagesSetupView(
                    onComplete: {
                        viewModel.currentStep = .featureOverview
                    },
                    onBack: {
                        viewModel.currentStep = .platformSelection
                    }
                )
            case .featureOverview:
                FeatureOverviewView(
                    onComplete: {
                        AppStateManager.shared.hasSetup = true
                        NSApplication.shared.keyWindow?.close()
                    }
                )
            }
        }
        .onAppear {
            viewModel.startMonitoring()
        }
        .onDisappear {
            viewModel.stopMonitoring()
        }
    }
}

struct IMessagePermissionsView: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                Image("logo")
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 60)

                Text("Welcome to CopyThat")
                    .font(.system(size: 24, weight: .bold))

                Text("Automatically copy verification codes from iMessage")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 30)
            .padding(.bottom, 25)

            Divider()

            // Permissions Section
            VStack(alignment: .leading, spacing: 20) {
                Text("Required Permissions")
                    .font(.system(size: 18, weight: .semibold))
                    .padding(.bottom, 5)

                // Accessibility Permission
                PermissionRow(
                    icon: "hand.raised.fill",
                    title: "Accessibility",
                    description: "Required for auto-paste and keyboard shortcuts",
                    status: viewModel.hasAccessibility ? .granted : .needed,
                    action: {
                        PermissionsService.acquireAccessibilityPrivileges()
                    }
                )

                // Full Disk Access Permission
                PermissionRow(
                    icon: "externaldrive.fill",
                    title: "Full Disk Access",
                    description: "Required to read verification codes from Messages",
                    status: viewModel.hasFullDiskAccess ? .granted : .needed,
                    action: {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                    }
                )
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 25)

            Button(action: {
                viewModel.checkPermissions()
            }) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh Status")
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(.blue)
            .padding(.bottom, 10)

            Spacer()

            // Status and Action
            HStack {
                Button(action: {
                    viewModel.currentStep = .platformSelection
                }) {
                    Text("Back")
                        .frame(minWidth: 80)
                }
                .buttonStyle(.bordered)

                Spacer()

                if viewModel.allPermissionsGranted {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("All permissions granted")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Grant permissions above to continue")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: {
                    if viewModel.allPermissionsGranted {
                        AppStateManager.shared.messagingPlatform = viewModel.selectedPlatform
                        viewModel.currentStep = .featureOverview
                    } else {
                        NSApplication.shared.keyWindow?.close()
                    }
                }) {
                    Text(viewModel.allPermissionsGranted ? "Next" : "Close")
                        .frame(minWidth: 80)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 20)
        }
        .frame(minWidth: 600, minHeight: 500)
    }
}

struct FeatureOverviewView: View {
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                Image("logo")
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 60)

                Text("How CopyThat Works")
                    .font(.system(size: 24, weight: .bold))
            }
            .padding(.top, 30)
            .padding(.bottom, 25)

            Divider()

            // Features Section
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    FeatureRow(
                        icon: "doc.on.clipboard.fill",
                        title: "Auto-Copy & Paste",
                        description: "CopyThat automatically extracts codes and copies them to your clipboard. If Accessibility is enabled, it even pastes them for you!"
                    )

                    FeatureRow(
                        icon: "bell.fill",
                        title: "Smart Notifications",
                        description: "See the code immediately in a custom overlay or native notification."
                    )

                    FeatureRow(
                        icon: "menubar.arrow.up.rectangle",
                        title: "Menu Bar Access",
                        description: "Access your last 3 codes anytime from the menu bar. No need to open Messages."
                    )

                    FeatureRow(
                        icon: "keyboard",
                        title: "Keyboard Shortcuts",
                        description: "Press ⌥⌘R to resync if iMessage misses a code. Use ⌘V to paste normally (CopyThat restores your original clipboard after 5 seconds)."
                    )
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 30)
            }

            Divider()

            // Action
            HStack {
                Spacer()
                Button(action: onComplete) {
                    Text("Got it, let's go!")
                        .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 20)
        }
        .frame(minWidth: 600, minHeight: 500)
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.blue)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let status: PermissionStatus
    let action: () -> Void

    var body: some View {
        HStack(spacing: 15) {
            // Icon
            ZStack {
                Circle()
                    .fill(status == .granted ? Color.blue.opacity(0.15) : Color.gray.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(status == .granted ? .blue : .gray)
            }

            // Text
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))

                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            // Status/Action
            if status == .granted {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Granted")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
            } else {
                Button("Grant Access") {
                    action()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(15)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

enum PermissionStatus {
    case granted
    case needed
}

class OnboardingViewModel: ObservableObject {
    @Published var currentStep: OnboardingStep = .platformSelection {
        didSet {
            NSLog("[CopyThat] Onboarding step changed to: \(currentStep.rawValue)")
            AppStateManager.shared.currentOnboardingStep = currentStep.rawValue
        }
    }
    @Published var selectedPlatform: MessagingPlatform = .iMessage
    @Published var hasAccessibility: Bool = false
    @Published var hasFullDiskAccess: Bool = false

    private var timer: Timer?

    var allPermissionsGranted: Bool {
        hasAccessibility && hasFullDiskAccess
    }

    init() {
        // Just check initial permissions
        checkPermissions()
    }

    func restoreState() {
        // Restore platform
        if AppStateManager.shared.hasSetup || AppStateManager.shared.currentOnboardingStep != nil {
            selectedPlatform = AppStateManager.shared.messagingPlatform
        }
        
        // Restore step
        if let savedStepRawValue = AppStateManager.shared.currentOnboardingStep,
           let savedStep = OnboardingStep(rawValue: savedStepRawValue) {
            NSLog("[CopyThat] Restoring onboarding step: \(savedStepRawValue)")
            self.currentStep = savedStep
        } else {
            NSLog("[CopyThat] No saved onboarding step found, starting at platformSelection")
        }
    }

    func proceedFromPlatformSelection() {
        switch selectedPlatform {
        case .iMessage:
            currentStep = .iMessagePermissions
        case .googleMessages:
            currentStep = .googleMessagesSetup
        }
    }

    func startMonitoring() {
        restoreState()
        checkPermissions()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkPermissions()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func checkPermissions() {
        hasAccessibility = AppStateManager.shared.hasAccessibilityPermission()
        hasFullDiskAccess = AppStateManager.shared.hasFullDiscAccess() == .authorized
        NSLog("[CopyThat] Permissions checked - Access: \(hasAccessibility), FDA: \(hasFullDiskAccess)")
    }
}

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView()
    }
}
