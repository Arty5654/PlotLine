import UIKit
import GoogleSignIn
import UserNotifications
//import LinkKit

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    
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

        // Check if this is a calendar event notification
        if let navigateTo = userInfo["navigateTo"] as? String, navigateTo == "calendar" {
            // Post a notification to navigate to calendar
            NotificationCenter.default.post(
                name: NSNotification.Name("NavigateToCalendar"),
                object: nil,
                userInfo: userInfo
            )
        }

        completionHandler()
    }
}
