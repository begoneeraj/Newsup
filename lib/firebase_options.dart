// Manually written to mirror what `flutterfire configure` would generate —
// values taken directly from android/app/google-services.json. Only Android
// is registered in the Firebase project; add ios/web blocks here if those
// platforms are registered later.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web — '
        'this project only registered an Android app in Firebase.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are only configured for Android in this project.',
        );
    }
  }

  static const android = FirebaseOptions(
    apiKey: 'AIzaSyDdS6RPoYdBazGu4-fDgOFYLFZ-jJAh8ys',
    appId: '1:396249525204:android:ae02c7e63a497015188441',
    messagingSenderId: '396249525204',
    projectId: 'newsup-db01f',
    storageBucket: 'newsup-db01f.firebasestorage.app',
  );
}
