import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Background notifications handle karne ke liye top-level function zaroori hai
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print("Handling a background message: ${message.messageId}");
  // Background me jab notification aaye to yahan logic handle ho sakti hai
}

class NotificationService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> initNotifications() async {
    // 1. Permission Request (iOS aur Android 13+ ke liye)
    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('✅ User granted permission');
    }

    // 2. Background Handler Register karein
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 3. Foreground Messages (Jab App Khuli Ho)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('📩 Foreground Message Received: ${message.notification?.title}');
      
      // Yahan aap local notification display karwa sakti hain agar zaroorat ho
    });
    
    // 4. App terminated state se notification click par khulne ke liye
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('🚀 Notification clicked and opened app!');
    });
  }

  // ── TOKEN LOGIC ──
  // Device ka unique token database me Rider ID ke sath save karne ke liye
  Future<void> saveRiderTokenToDatabase(String riderId) async {
    try {
      String? token = await _fcm.getToken();
      if (token != null) {
        await _firestore.collection('users').doc(riderId).set({
          'fcmToken': token,
        }, SetOptions(merge: true));
        print("🎯 FCM Token saved for rider: $token");
      }
    } catch (e) {
      print("❌ Error fetching/saving token: $e");
    }
  }
}