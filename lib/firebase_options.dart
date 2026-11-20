// File generated for RemedyTrack production deployment.
// ignore_for_file: lines_longer_than_80_chars, avoid_classes_with_only_static_members
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with RemedyTrack across Android, iOS, Web, and Desktop.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => android,
      TargetPlatform.iOS => ios,
      TargetPlatform.macOS => macos,
      TargetPlatform.windows => windows,
      _ => throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        ),
    };
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBZ5v7ZyWgHH0GFcj-z2OW-8b6uQ_ttEu8',
    appId: '1:468984717069:web:b998424ba7703a53565a44',
    messagingSenderId: '468984717069',
    projectId: 'remedy-track',
    authDomain: 'remedy-track.firebaseapp.com',
    storageBucket: 'remedy-track.firebasestorage.app',
    measurementId: 'G-W9Z0PL2ZZV',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBVonMlE3EIVoGwbl3doWeu_PJ5EL44EEA',
    appId: '1:468984717069:android:63e477296fbdfae5565a44',
    messagingSenderId: '468984717069',
    projectId: 'remedy-track',
    storageBucket: 'remedy-track.firebasestorage.app',
  );
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBNdu_ZBMMfzlqG54suKm4dh1rrzicHbgk',
    appId: '1:468984717069:ios:969a6a0344949c09565a44',
    messagingSenderId: '468984717069',
    projectId: 'remedy-track',
    storageBucket: 'remedy-track.firebasestorage.app',
    iosBundleId: 'com.remedytrack.app',
  );
  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyBNdu_ZBMMfzlqG54suKm4dh1rrzicHbgk',
    appId: '1:468984717069:ios:e5d5e05e92638011565a44',
    messagingSenderId: '468984717069',
    projectId: 'remedy-track',
    storageBucket: 'remedy-track.firebasestorage.app',
    iosBundleId: 'com.remedytrack.app',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyBZ5v7ZyWgHH0GFcj-z2OW-8b6uQ_ttEu8',
    appId: '1:468984717069:web:1faf2ebe902b1e5a565a44',
    messagingSenderId: '468984717069',
    projectId: 'remedy-track',
    authDomain: 'remedy-track.firebaseapp.com',
    storageBucket: 'remedy-track.firebasestorage.app',
    measurementId: 'G-VX77V99CC5',
  );
}
