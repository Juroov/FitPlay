# FitPlay

FitPlay is a Flutter workout planner and gym-session tracker. It supports
email/password and Google authentication, reusable workout routines, weekly
scheduling, timed sessions, completion history, themes, and unit preferences.

## Run locally

Requirements:

- Flutter 3.44 or newer
- Dart 3.12 or newer
- Chrome for web, or an Android device/emulator

```sh
flutter pub get
flutter run -d chrome
```

Android is also configured:

```sh
flutter run -d android
```

Firebase is configured for web and Android. On Windows, macOS, Linux, and iOS,
the app remains runnable in local demo mode until platform credentials are
generated with `flutterfire configure`.

## Verification

```sh
flutter analyze
flutter test
```

## Firebase

Before a public deployment, deploy the checked-in Firestore security rules:

```sh
firebase deploy --only firestore:rules
```

Use separate Firebase projects for development and production, enable the
desired authentication providers in Firebase Console, and enable App Check for
production builds.
