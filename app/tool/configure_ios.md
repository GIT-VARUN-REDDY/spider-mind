# iOS setup (needs a Mac with Xcode)

1. `flutter create --org com.spider --project-name spider_mind --platforms=android,ios .` (once, inside `app/`).
2. In `ios/Runner/AppDelegate.swift`, inside `application(_:didFinishLaunchingWithOptions:)` before `return`:
   ```swift
   if #available(iOS 10.0, *) {
     UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
   }
   ```
3. In Xcode set your Team and bundle id. Notifications use the standard permission prompt (Settings > Reminders > Allow).
4. For HTTPS-only APIs nothing else is needed. For a plain `http://` dev server add an App Transport Security exception in `Info.plist`.
5. `flutter build ipa --release --dart-define=API_URL=https://your-api`
