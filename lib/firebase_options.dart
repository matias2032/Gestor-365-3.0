// File generated manually to include Windows support.
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.windows:
        return windows; // Suporte para Windows ativado aqui
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = windows; // Windows usa as mesmas chaves de Web

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyC5p3ISXWUb49L41GqthVz2Jc0POqtumCs',
    appId: '1:1076602142855:android:f5a4752311320edbae7822',
    messagingSenderId: '1076602142855',
    projectId: 'gestor365push1',
    storageBucket: 'gestor365push1.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyB4_yVH6TNZUQAgl4u3ahCSCebjMcJCdqE',
    appId: '1:1076602142855:ios:1443c75f5b580880ae7822',
    messagingSenderId: '1076602142855',
    projectId: 'gestor365push1',
    storageBucket: 'gestor365push1.firebasestorage.app',
    iosBundleId: 'com.example.gestaoBarPos',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyC5HGFMq68BHxfq6K8WaZ3fRRt6yebT80',
    appId: '1:1076602142855:web:8f75d0b0132b9506ae7822',
    messagingSenderId: '1076602142855',
    projectId: 'gestor365push1',
    authDomain: 'gestor365push1.firebaseapp.com',
    storageBucket: 'gestor365push1.firebasestorage.app',
  );
}