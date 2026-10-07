//
//  AppBanner.swift
//  PlotLine
//
//  The app-wide error banner: "Couldn't save your meal. Check your connection and try again."
//  Any screen reports a failure with one line:
//
//      AppBanner.report("save your meal", error)
//      AppBanner.report("load your budget", error, retry: { loadBudget() })
//
//  It slides in at the top above everything (sheets and alerts included) from its own small
//  window that only covers the banner's strip, so the rest of the screen keeps working.
//  Background work the person didn't ask for (widgets, badge, prefetching) shouldn't report.
//

import SwiftUI
import UIKit

@MainActor
final class AppBanner: ObservableObject {
    static let shared = AppBanner()

    struct Message: Identifiable {
        let id = UUID()
        let text: String
        let retry: (@MainActor () -> Void)?
        var isOffline: Bool { text.hasSuffix(AppBanner.offlineHint) }
    }

    @Published private(set) var message: Message?

    private var window: UIWindow?
    private var hideTask: Task<Void, Never>?

    private init() { }

    /// Report a failure from anywhere (any thread). `action` finishes "Couldn't …", e.g. "save your meal".
    nonisolated static func report(_ action: String, _ error: Error? = nil, retry: (@MainActor () -> Void)? = nil) {
        let text = text(for: action, error)
        print("⚠️ Couldn't \(action): \(error.map { "\($0)" } ?? "no details")")
        Task { @MainActor in shared.show(text, retry: retry) }
    }

    /// For completion-handler requests: reports and returns true unless the request worked (2xx).
    @discardableResult
    nonisolated static func reportIfFailed(_ action: String, _ data: Data?, _ response: URLResponse?, _ error: Error?,
                                           retry: (@MainActor () -> Void)? = nil) -> Bool {
        if let error {
            report(action, error, retry: retry)
            return true
        }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            switch (response as? HTTPURLResponse)?.statusCode {
            case 402: // membership ended: the paywall explains it, no banner needed
                Task { @MainActor in await MembershipManager.shared.refresh() }
            case 401: // login no longer valid: check the session (signs out if it expired)
                NotificationCenter.default.post(name: .plotlineSessionRejected, object: nil)
            default:
                report(action, AILimitError.from(data, response) ?? URLError(.badServerResponse), retry: retry)
            }
            return true
        }
        return false
    }

    /// What the banner says. Offline gets its own hint; the daily AI limit keeps the server's wording.
    nonisolated static func text(for action: String, _ error: Error?) -> String {
        if let limit = error as? AILimitError { return limit.message }
        if let urlError = error as? URLError, offlineCodes.contains(urlError.code) {
            return "Couldn't \(action). \(offlineHint)"
        }
        return "Couldn't \(action). Please try again."
    }

    nonisolated static let offlineHint = "Check your connection and try again."

    private nonisolated static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost,
        .cannotFindHost, .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff,
    ]

    func show(_ text: String, retry: (@MainActor () -> Void)? = nil) {
        // the same problem again, or another thing that failed because they're offline: keep the one that's showing
        if let current = message, current.text == text || (current.isOffline && text.hasSuffix(Self.offlineHint)) {
            if current.retry == nil || retry == nil {
                scheduleHide()
                return
            }
        }
        installWindow()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            message = Message(text: text, retry: retry)
        }
        UIAccessibility.post(notification: .announcement, argument: text)
        scheduleHide()
    }

    func dismiss() {
        hideTask?.cancel()
        withAnimation(.easeOut(duration: 0.25)) { message = nil }
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            if message == nil { window?.isHidden = true }
        }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        let seconds = message?.retry != nil ? 8.0 : 5.0
        hideTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    // a window just tall enough for the banner, above sheets and alerts
    private func installWindow() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) ?? UIApplication.shared.connectedScenes.first as? UIWindowScene
        else { return }
        let topInset = scene.windows.first(where: \.isKeyWindow)?.safeAreaInsets.top ?? 47
        let frame = CGRect(x: 0, y: 0, width: scene.screen.bounds.width, height: topInset + 96)

        if window == nil || window?.windowScene !== scene {
            let bannerWindow = UIWindow(windowScene: scene)
            bannerWindow.windowLevel = .alert + 1
            bannerWindow.backgroundColor = .clear
            let host = UIHostingController(rootView: AppBannerView(banner: self))
            host.view.backgroundColor = .clear
            bannerWindow.rootViewController = host
            window = bannerWindow
        }
        window?.frame = frame
        window?.isHidden = false
    }
}

extension NSNotification.Name {
    /// the server said "please sign in again" (PlotLineApp re-checks the session)
    static let plotlineSessionRejected = NSNotification.Name("PlotLineSessionRejected")
}

private struct AppBannerView: View {
    @ObservedObject var banner: AppBanner

    var body: some View {
        VStack {
            if let message = banner.message {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(message.text)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    if let retry = message.retry {
                        Button("Try again") {
                            banner.dismiss()
                            retry()
                        }
                        .font(.subheadline.weight(.bold))
                    }
                    Button {
                        banner.dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.bold))
                            .foregroundColor(.secondary)
                    }
                    .accessibilityLabel("Dismiss")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.35)))
                .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                .padding(.horizontal, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
                .gesture(DragGesture(minimumDistance: 10).onEnded { value in
                    if value.translation.height < 0 { banner.dismiss() } // swipe up to dismiss
                })
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity)
    }
}
