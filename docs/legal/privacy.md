# Privacy Policy for Project Spider

**Last Updated:** November 4, 2026

## 1. Introduction
Project Spider ("we", "our", or "the App") is an offline-first visual task, idea, and goal management platform that organizes thoughts as an interactive 3D web. We respect your privacy and are committed to protecting your personal data.

## 2. Information We Collect
- **Account Information:** Email address, display name, and password (securely hashed with bcrypt).
- **User Content:** Threads, spaces, links, checklists, reminders, and tags that you create within the App.
- **Local Device Cache:** Stored securely on your device using encrypted storage (`FlutterSecureStorage`) and local device preferences (`SharedPreferences`) to provide offline capability.
- **Diagnostics and Telemetry:** Basic error and sync status information necessary to resolve real-time sync anomalies.

## 3. How We Use Your Data
- To synchronize your threads and spaces across your authorized devices in real time using secure WebSockets and REST APIs.
- To schedule timely, on-device local notifications and reminders without sending continuous background data to external parties.
- To maintain account security, authenticate sessions, and issue cryptographically signed JWT tokens.

## 4. Data Storage and Security
- All network communications between the App and the API server are encrypted via TLS/HTTPS.
- Passwords are salted and hashed using bcrypt (cost factor >= 10).
- Data stored locally on mobile devices remains under your control and is completely purged when you choose "Sign Out" or "Delete Account".

## 5. Third-Party Services
Project Spider does not sell, trade, or monetize your personal content or metadata. We do not incorporate third-party advertising trackers. Optional push notifications are routed solely through secure platform providers (e.g., Apple APNs or Google FCM).

## 6. User Rights and Deletion
You retain complete ownership of your data. You may at any time:
- Export your full database in JSON format directly from the **Settings > Data > Export JSON** screen.
- Permanently erase your account and all associated threads, spaces, and activity records via **Settings > Account > Delete Account**.

## 7. Contact Us
For questions regarding this Privacy Policy or your data, please contact the maintainers at `privacy@spidermind.app`.
