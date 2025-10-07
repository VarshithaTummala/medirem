# MediRem

A Flutter app that helps users set medication reminders with local notifications and optional FCM push.

## Features
- Create, edit, and cancel medication reminders
- Local notifications (Android) via `flutter_local_notifications`
- Optional Firebase Cloud Messaging integration

## Build (Android)
```bash
# get deps
flutter pub get

# debug run
flutter run

# release APK
flutter build apk --release

# release App Bundle (Play Store)
flutter build appbundle --release

## 📱 Screenshots

### Welcome Screen
<img src="assets/screenshots/welcome_screen.jpeg" width="300">

### Home Screen
<img src="assets/screenshots/home_screen.jpeg" width="300">

### Set Reminder Screen
<img src="assets/screenshots/set_reminder_screen1.png" width="300">

<img src="assets/screenshots/set_reminder_screen2.png" width="300">

<img src="assets/screenshots/set_reminder_screen3.png" width="300">

### Notification Example
<img src="assets/screenshots/alarm_screen.png" width="300">
