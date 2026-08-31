import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class FcmService {
  // ── CHANGED ──────────────────────────────────────────────────
  // The old syncDeviceToken() POSTed to '$backendUrl/api/users/fcm-token',
  // but that route was never defined in server.js — every call would
  // have 404'd. It was also never actually called from anywhere in the
  // app (login/signup never imported FcmService), so the token never
  // reached the backend in the first place.
  //
  // Fix: save the token directly to Firestore on users/{uid}, the same
  // way the rest of the app already stores per-user fields like
  // branchId. Whatever server-side code sends the push (the Node.js
  // /send-notification route, or a Cloud Function) should read
  // users/{uid}.fcmToken from Firestore to know which token to target.
  // ─────────────────────────────────────────────────────────────

  /// Requests notification permission, gets this device's current FCM
  /// token, and saves it to the user's Firestore doc. Call this right
  /// after a successful login or signup (once `userId` is known).
  static Future<void> syncDeviceToken(String userId) async {
    if (userId.isEmpty) return;

    final messaging = FirebaseMessaging.instance;

    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    final authorized =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    if (!authorized) return; // user denied notification permission

    final token = await messaging.getToken();
    if (token == null) return;

    await FirebaseFirestore.instance.collection('users').doc(userId).set(
      {'fcmToken': token},
      SetOptions(merge: true),
    );
  }

  /// Keeps the saved token current if Firebase rotates it while the
  /// user stays logged in (token refresh can happen at any time, not
  /// just at login). Call this once per app session — e.g. in
  /// main.dart / AuthWrapper — after you know the current userId.
  static void listenForTokenRefresh(String userId) {
    if (userId.isEmpty) return;
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      FirebaseFirestore.instance.collection('users').doc(userId).set(
        {'fcmToken': newToken},
        SetOptions(merge: true),
      );
    });
  }

  /// Optional: call on logout so a stale token isn't left pointing at
  /// a device that's no longer signed in as this user.
  static Future<void> clearDeviceToken(String userId) async {
    if (userId.isEmpty) return;
    await FirebaseFirestore.instance.collection('users').doc(userId).set(
      {'fcmToken': FieldValue.delete()},
      SetOptions(merge: true),
    );
  }
}
