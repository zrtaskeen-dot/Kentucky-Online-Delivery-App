import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  Future<void> initNotifications() async {
    
    tzdata.initializeTimeZones();

    NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('User granted notification permission');
    }

    
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const initSettings = InitializationSettings(android: androidSettings);
    await _localNotifications.initialize(initSettings);

    
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print(
        'Foreground Message Received (in-app only, no bar popup): '
        '${message.notification?.title}',
      );
    });

    
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print(' Notification clicked and opened app!');
    });
  }

 
  Future<void> checkInitialMessage() async {
    RemoteMessage? initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      print(
        "App opened from terminated state via notification: ${initialMessage.data}",
      );
    }
  }

 
  
  Future<void> saveRiderTokenToDatabase(String riderId) async {
    try {
      String? token = await _messaging.getToken();
      if (token != null) {
        await _firestore.collection('users').doc(riderId).set({
          'fcmToken': token,
        }, SetOptions(merge: true));
        print("FCM Token saved for rider: $token");
      }
    } catch (e) {
      print("Error fetching/saving token: $e");
    }
  }

  //  IN-APP notification 
  static Future<void> notifyCustomer({
    required String customerId,
    required String title,
    required String body,
  }) async {
    if (customerId.isEmpty) return;
    await FirebaseFirestore.instance.collection('notifications').add({
      'userId': customerId,
      'title': title,
      'body': body,
      'isRead': false,
      'hiddenFor': <String>[], 
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Sends an in-app notification to ALL customers
 
  static Future<void> broadcastToAllCustomers({
    required String title,
    required String body,
  }) async {
    await FirebaseFirestore.instance.collection('notifications').add({
      'userId': 'ALL',
      'title': title,
      'body': body,
      'isRead': false,
      'hiddenFor': <String>[], 
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  
  Future<void> scheduleReceiptUploadReminder({
    required String orderId,
    required DateTime scheduledOrderTime,
  }) async {
    final reminderTime = scheduledOrderTime.subtract(
      const Duration(hours: 1, minutes: 30),
    );

    
    if (reminderTime.isBefore(DateTime.now())) {
      print('Receipt reminder skipped - scheduled time is under 1h30m away.');
      return;
    }

    try {
      await _localNotifications.zonedSchedule(
        orderId.hashCode,
        'Payment Now Available',
        'You can now upload your payment for your scheduled order. It will only be confirmed once payment is completed.',
        tz.TZDateTime.from(reminderTime, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'high_importance_channel',
            'High Importance Notifications',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
        payload: orderId,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
      print('Receipt reminder scheduled for order $orderId at $reminderTime');
    } catch (e) {
      print('Error scheduling receipt reminder: $e');
    }
  }

  
  Future<void> cancelReceiptUploadReminder(String orderId) async {
    await _localNotifications.cancel(orderId.hashCode);
  }

  // Delete Notification from customer list 
  
  static Future<void> hideNotificationForUser({
    required String notificationId,
    required String userId,
  }) async {
    final ref = FirebaseFirestore.instance
        .collection('notifications')
        .doc(notificationId);
    final snap = await ref.get();
    if (!snap.exists) return;

    final ownerId = (snap.data()?['userId'] ?? '').toString();
    if (ownerId == 'ALL') {
      
      await ref.update({
        'hiddenFor': FieldValue.arrayUnion([userId]),
      });
    } else if (ownerId == userId) {
      
      await ref.delete();
    }
  }

 
  static Future<void> hideAllNotificationsForUser(String customerId) async {
    final snap = await FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', whereIn: [customerId, 'ALL'])
        .get();

    if (snap.docs.isEmpty) return;

    final batch = FirebaseFirestore.instance.batch();
    for (final doc in snap.docs) {
      final ownerId = (doc.data()['userId'] ?? '').toString();
      if (ownerId == 'ALL') {
        
        batch.update(doc.reference, {
          'hiddenFor': FieldValue.arrayUnion([customerId]),
        });
      } else {
        //  customer's own notification delete it from Firestore
        batch.delete(doc.reference);
      }
    }
    await batch.commit();
  }

  

  static Future<void> deleteNotification(String notificationId) async {
    await FirebaseFirestore.instance
        .collection('notifications')
        .doc(notificationId)
        .delete();
  }

  static Future<void> deleteAllNotificationsForUser(String customerId) async {
    final snap = await FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: customerId)
        .get();

    if (snap.docs.isEmpty) return;

    final batch = FirebaseFirestore.instance.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }
}
