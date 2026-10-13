// File generated with Firebase configuration options for fittrack-605d0
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        return android;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCpZejhhAEhyI37y8OcOxwOq1RoBtaSEdU',
    appId: '1:1039199888579:web:4f79c90d5fde5c58bbae76',
    messagingSenderId: '1039199888579',
    projectId: 'fittrack-605d0',
    authDomain: 'fittrack-605d0.firebaseapp.com',
    storageBucket: 'fittrack-605d0.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCpZejhhAEhyI37y8OcOxwOq1RoBtaSEdU',
    appId: '1:1039199888579:android:4f79c90d5fde5c58bbae76',
    messagingSenderId: '1039199888579',
    projectId: 'fittrack-605d0',
    storageBucket: 'fittrack-605d0.firebasestorage.app',
  );
}
