//
//  SupportMail.swift
//  PlotLine
//
//  Profile → Email Us: writes to support with the app version and phone model filled in (so we
//  know what they're running). Uses the Mail app sheet when Mail is set up, another mail app
//  otherwise, and as a last resort shows the address to copy.
//

import SwiftUI
import MessageUI
import UIKit

enum SupportMail {
    static let address = "plotlineemail@gmail.com"
    static let subject = "PlotLine Support"

    /// the details at the bottom of the email
    static func diagnostics(username: String) -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        var system = utsname()
        uname(&system)
        let model = withUnsafeBytes(of: &system.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return """


        ---
        Please write above this line.
        App: PlotLine \(version) (\(build))
        iOS: \(UIDevice.current.systemVersion)
        Device: \(model)
        Username: \(username.isEmpty ? "not signed in" : username)
        """
    }

    static func mailtoURL(username: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [URLQueryItem(name: "subject", value: subject),
                                 URLQueryItem(name: "body", value: diagnostics(username: username))]
        return components.url
    }
}

/// the Mail app's compose sheet
struct MailComposeView: UIViewControllerRepresentable {
    let username: String
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.setToRecipients([SupportMail.address])
        vc.setSubject(SupportMail.subject)
        vc.setMessageBody(SupportMail.diagnostics(username: username), isHTML: false)
        vc.mailComposeDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: MFMailComposeViewController, context: Context) { }

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: { dismiss() }) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let dismiss: () -> Void
        init(dismiss: @escaping () -> Void) { self.dismiss = dismiss }
        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult, error: Error?) {
            dismiss()
        }
    }
}

/// "Email Us" row for Profile: the right way to write to support on this phone
struct SupportRow: View {
    let username: String
    @Environment(\.openURL) private var openURL
    @State private var showCompose = false
    @State private var showAddress = false

    var body: some View {
        Button {
            if MFMailComposeViewController.canSendMail() {
                showCompose = true
            } else if let url = SupportMail.mailtoURL(username: username), UIApplication.shared.canOpenURL(url) {
                openURL(url) // Gmail, Outlook, ... set as the mail app
            } else {
                showAddress = true
            }
        } label: {
            PLRow(icon: "envelope.fill", tint: .blue, title: "Email Us")
        }
        .sheet(isPresented: $showCompose) {
            MailComposeView(username: username).ignoresSafeArea()
        }
        .alert("Email Us", isPresented: $showAddress) {
            Button("Copy Address") { UIPasteboard.general.string = SupportMail.address }
            Button("OK", role: .cancel) { }
        } message: {
            Text("No mail app is set up on this phone. Write to us at \(SupportMail.address) — questions, problems and ideas are all welcome.")
        }
    }
}
