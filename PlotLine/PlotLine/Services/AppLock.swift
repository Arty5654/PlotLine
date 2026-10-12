//
//  AppLock.swift
//  PlotLine
//
//  Profile → Lock with Face ID. When it's on, opening PlotLine asks for Face ID (or the phone's
//  passcode), and so does coming back after more than a minute away. While the app is in the
//  background or the app switcher, its screen is covered so balances and spending aren't visible.
//
//  The lock and the cover are their own window above everything (sheets and alerts included).
//

import LocalAuthentication
import SwiftUI
import UIKit

@MainActor
final class AppLock: ObservableObject {
    static let shared = AppLock()

    static let relockAfter: TimeInterval = 60
    private static let enabledKey = "appLockEnabled"

    @Published private(set) var isEnabled: Bool
    @Published private(set) var locked = false
    @Published private(set) var covered = false

    private var leftAt: Date?
    private var hasLaunched = false
    private var prompting = false
    private var promptedForThisLock = false
    private var window: UIWindow?

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    // MARK: - Settings

    /// "Face ID", "Touch ID", or "Passcode" (a phone without biometrics uses its passcode)
    static var methodName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }

    /// a phone with no passcode can't lock anything
    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// turning it on (or off) asks for Face ID first, so someone else can't change it
    func setEnabled(_ on: Bool) async {
        guard on != isEnabled else { return }
        guard await authenticate(reason: on ? "Turn on the PlotLine lock" : "Turn off the PlotLine lock") else { return }
        isEnabled = on
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
    }

    // MARK: - App life

    func sceneChanged(to phase: ScenePhase) {
        switch phase {
        case .active:
            covered = false
            let firstLaunch = !hasLaunched
            hasLaunched = true
            if isEnabled, !locked, firstLaunch || (leftAt.map { Date().timeIntervalSince($0) >= Self.relockAfter } ?? false) {
                locked = true
                promptedForThisLock = false
            }
            leftAt = nil
            if locked {
                showWindow()
                if !promptedForThisLock { // once per lock; after a cancel, the Unlock button asks again
                    promptedForThisLock = true
                    Task { await unlock() }
                }
            } else {
                hideWindow()
            }
        case .inactive:
            // the app switcher shows the app as it is now: cover it
            if isEnabled, !prompting {
                covered = true
                showWindow()
            }
        case .background:
            if isEnabled {
                covered = true
                showWindow()
                if leftAt == nil { leftAt = Date() }
            }
        @unknown default:
            break
        }
    }

    func unlock() async {
        guard locked, !prompting else { return }
        if await authenticate(reason: "Unlock PlotLine") {
            locked = false
            hideWindow()
        }
    }

    /// signing out: the next person shouldn't inherit the lock prompt mid-way
    func reset() {
        locked = false
        covered = false
        hideWindow()
    }

    private func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        prompting = true
        defer { prompting = false }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }

    // MARK: - Window

    private func showWindow() {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        if window == nil || window?.windowScene !== scene {
            let lockWindow = UIWindow(windowScene: scene)
            lockWindow.windowLevel = .alert + 10 // above sheets, alerts and banners
            let host = UIHostingController(rootView: AppLockView(lock: self))
            host.view.backgroundColor = .clear
            lockWindow.rootViewController = host
            window = lockWindow
        }
        window?.isHidden = false
    }

    private func hideWindow() {
        window?.isHidden = true
    }
}

struct AppLockView: View {
    @ObservedObject var lock: AppLock

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: PLSpacing.lg) {
                Image("PlotLineLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                if lock.locked {
                    Text("PlotLine is locked")
                        .font(.headline)
                    Button {
                        Task { await lock.unlock() }
                    } label: {
                        Label("Unlock with \(AppLock.methodName)",
                              systemImage: AppLock.methodName == "Face ID" ? "faceid" : AppLock.methodName == "Touch ID" ? "touchid" : "lock.open")
                            .frame(maxWidth: 280)
                    }
                    .buttonStyle(PrimaryButton())
                    .padding(.horizontal, PLSpacing.lg)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Profile → Security
struct AppLockToggle: View {
    @ObservedObject private var lock = AppLock.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(get: { lock.isEnabled }, set: { on in Task { await lock.setEnabled(on) } })) {
                Label("Lock with \(AppLock.methodName)",
                      systemImage: AppLock.methodName == "Touch ID" ? "touchid" : AppLock.methodName == "Passcode" ? "lock.fill" : "faceid")
            }
            .tint(PLColor.success)
            .disabled(!AppLock.isAvailable)
            Text(AppLock.isAvailable
                 ? "Asks for \(AppLock.methodName) when you open PlotLine and after a minute away. Your balances are hidden in the app switcher."
                 : "Set a passcode for this iPhone in Settings to lock PlotLine.")
                .font(.caption)
                .foregroundColor(PLColor.textSecondary)
        }
    }
}
