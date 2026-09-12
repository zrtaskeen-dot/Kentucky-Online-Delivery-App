import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class FcmService {
 
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
