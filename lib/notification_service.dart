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
    // Needed for zonedSchedule() below to fire reminders at the correct
    // real-world time (not UTC). setLocalLocation defaults to UTC if never
    // called — if your users span multiple timezones, replace 'local' with
    // the device's real IANA timezone name (e.g. via the flutter_timezone
    // package) instead of relying on the system default here.
    tzdata.initializeTimeZones();

    // 1. Permission request (iOS aur Android 13+ ke liye)
    NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('User granted notification permission');
    }

    // 2. Local notification plugin setup — still needed for the scheduled
    // "upload receipt" reminder below (scheduleReceiptUploadReminder), but
    // NOT used anymore to pop up incoming FCM messages (see listener below).
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const initSettings = InitializationSettings(android: androidSettings);
    await _localNotifications.initialize(initSettings);

    // 3. Foreground listener — app khuli ho tab notification-bar popup
    // NAHI dikhana (in-app only ab). We still log it for debugging, but
    // deliberately do NOT call _localNotifications.show() here anymore —
    // the actual customer-visible notification is the Firestore
    // 'notifications' doc written by notifyCustomer()/broadcastToAllCustomers(),
    // which NotificationScreen and the bottom-nav badge already show live,
    // inside the app.
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print(
        'Foreground Message Received (in-app only, no bar popup): '
        '${message.notification?.title}',
      );
    });

    // 4. Background state se notification tap karke app open karne par
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print(' Notification clicked and opened app!');
    });
  }

  //  Terminated state se app open hone par (main.dart mein call hoti hai)
  Future<void> checkInitialMessage() async {
    RemoteMessage? initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      print(
        "App opened from terminated state via notification: ${initialMessage.data}",
      );
    }
  }

  // ── TOKEN LOGIC ──
  // Device ka unique FCM token, Rider ID ke sath Firestore me save karta hai
  // (RiderHomeScreen ke initState() mein call hoti hai)
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

  // ── IN-APP NOTIFICATIONS ──
  // These just write a document to Firestore's `notifications` collection.
  // No Cloud Functions, no backend server — NotificationScreen already
  // listens to this collection in real time via a StreamBuilder, so any
  // screen in the app (rider status update, manager cancelling an order,
  // manager adding a menu item) can call these to instantly put something
  // in the customer's notification list.

  /// Sends an in-app notification to ONE specific customer.
  /// Use for order-specific events: accepted, picked up, on the way,
  /// delivered, cancelled.
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
      'hiddenFor': <String>[], // per-user "deleted from UI" list
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Sends an in-app notification to ALL customers.
  /// Use for store-wide events: a new menu item or a new deal.
  static Future<void> broadcastToAllCustomers({
    required String title,
    required String body,
  }) async {
    await FirebaseFirestore.instance.collection('notifications').add({
      'userId': 'ALL',
      'title': title,
      'body': body,
      'isRead': false,
      'hiddenFor': <String>[], // per-user "deleted from UI" list
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  // ── SCHEDULED RECEIPT-UPLOAD REMINDER ──
  // For a scheduled ('order later') order paid via Online payment, the
  // customer doesn't upload their payment screenshot at checkout — they
  // upload it 1 hour before the scheduled delivery time instead. This
  // schedules a device-local notification (fires even if the app is
  // closed) at that moment, reminding them to open the order and upload
  // the receipt so it gets confirmed.
  Future<void> scheduleReceiptUploadReminder({
    required String orderId,
    required DateTime scheduledOrderTime,
  }) async {
    final reminderTime = scheduledOrderTime.subtract(const Duration(hours: 1));

    // If the order is already less than an hour away (or in the past),
    // there's no "1 hour before" moment left to schedule — skip silently.
    if (reminderTime.isBefore(DateTime.now())) {
      print('Receipt reminder skipped — scheduled time is under an hour away.');
      return;
    }

    try {
      await _localNotifications.zonedSchedule(
        orderId.hashCode,
        'Upload Your Payment Receipt',
        'Your scheduled order is in 1 hour — upload your payment receipt now to confirm it.',
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

  /// Cancels a previously scheduled receipt-upload reminder — call this if
  /// the customer already uploaded the receipt early, or cancels the order.
  Future<void> cancelReceiptUploadReminder(String orderId) async {
    await _localNotifications.cancel(orderId.hashCode);
  }

  // ── HIDE NOTIFICATIONS (UI-only "delete") ──
  // These do NOT remove anything from Firestore. They add the customer's
  // uid to the document's `hiddenFor` array, and NotificationScreen filters
  // out any doc whose `hiddenFor` contains the current user's uid. Data
  // stays in the database forever (for records/analytics/other users —
  // important for 'ALL' broadcast docs, which are shared across everyone),
  // it just disappears from that one customer's list.

  /// Hides a single notification from [userId]'s list only. Works for both
  /// personal notifications and 'ALL' broadcasts — a broadcast hidden this
  /// way still shows normally to every other customer.
  static Future<void> hideNotificationForUser({
    required String notificationId,
    required String userId,
  }) async {
    await FirebaseFirestore.instance
        .collection('notifications')
        .doc(notificationId)
        .update({
          'hiddenFor': FieldValue.arrayUnion([userId]),
        });
  }

  /// Hides every notification (personal + broadcast) currently visible to
  /// [customerId] — i.e. clears their whole list — without touching the
  /// documents for anyone else.
  static Future<void> hideAllNotificationsForUser(String customerId) async {
    final snap = await FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', whereIn: [customerId, 'ALL'])
        .get();

    if (snap.docs.isEmpty) return;

    final batch = FirebaseFirestore.instance.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {
        'hiddenFor': FieldValue.arrayUnion([customerId]),
      });
    }
    await batch.commit();
  }

  // ── OLD HARD-DELETE HELPERS (kept for admin/cleanup use if ever needed —
  // NOT used by NotificationScreen anymore, since deletes there are now
  // hide-only. Call these yourself only if you actually want to permanently
  // erase a document from Firestore.) ──

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
