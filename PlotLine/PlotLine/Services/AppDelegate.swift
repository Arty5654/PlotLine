import UIKit
import GoogleSignIn
import UserNotifications
//import LinkKit

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    // Store pending notification navigation for cold starts
    static var pendingNotificationUserInfo: [AnyHashable: Any]? = nil

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Correct place to set the delegate
        UNUserNotificationCenter.current().delegate = self
        
        return true
    }
    
    func application(
        _ app: UIApplication,
        open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]
    ) -> Bool {
        var handled: Bool

        handled = GIDSignIn.sharedInstance.handle(url)
        if handled {
            return true
        }
        
//        if Plaid.canHandleRedirectURL(url) {
//            Plaid.handleRedirectURL(url)
//            return true
//        }


        return false
    }

    // push notifications from the server: this phone's address
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushRegistration.didRegister(token: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Push registration failed: \(error.localizedDescription)") // e.g. the Simulator without push support
    }

    // a push from the server says which screen it's about ("friends", "calendar", "grocery", "budget")
    static var pendingDestination: String?

    // Ensure notifications appear in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        print("Notification received while app is in foreground")
        completionHandler([.banner, .sound, .badge])
    }

    // Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        if let destination = userInfo["destination"] as? String {
            AppDelegate.pendingDestination = destination // the app may still be starting
            NotificationCenter.default.post(name: .plotlineDeepLink, object: nil, userInfo: ["destination": destination])
        }

        // a goal reminder: open that goal (works whether the app was running or not)
        if userInfo["navigateTo"] as? String == "goals" {
            let info = userInfo
            Task { @MainActor in GoalsRouter.shared.open(info) }
        }

        // Check if this is a calendar event notification
        if let navigateTo = userInfo["navigateTo"] as? String, navigateTo == "calendar" {
            // Store for cold start case (when ContentView isn't ready yet)
            AppDelegate.pendingNotificationUserInfo = userInfo

            // Post a notification to navigate to calendar (for warm start case)
            NotificationCenter.default.post(
                name: NSNotification.Name("NavigateToCalendar"),
                object: nil,
                userInfo: userInfo
            )
        }

        completionHandler()
    }
}
