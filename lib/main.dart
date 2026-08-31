import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'cart_provider.dart';
import 'logic/notification_service.dart';
import '/auth_wrapper.dart';
import 'global_feedback_listener.dart';
import 'logic/rider_logic.dart';

// Screens for Deep Linking Navigation
import 'live_tracking.dart';
import 'order_history.dart';
// Import your Rider assigned orders screen here, e.g.:
// import 'rider_assigned_orders_screen.dart';

// Global Key for programmatic navigation upon notification tap
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Top-level function for background FCM messages
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("Handling a background message: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();

    // 1. Set background message handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 2. Initialize local notifications and FCM listeners
    await NotificationService().initNotifications();

    // 3. Check for notification click from terminated state
    await NotificationService().checkInitialMessage();

    print("Firebase and FCM Initialized Successfully");
  } catch (e) {
    print("Firebase Initialization Error: $e");
  }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    _setupNotificationNavigation();
  }

  void _setupNotificationNavigation() {
    // 1. Handle app launch from Terminated State when notification is tapped
    FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        _handleDeepLink(message.data);
      }
    });

    // 2. Handle notification tap when app is in Background State
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleDeepLink(message.data);
    });
  }

  void _handleDeepLink(Map<String, dynamic> data) {
    final String? screen = data['screen'];
    final String? orderId = data['orderId'];

    if (screen == 'live_tracking' && orderId != null) {
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => LiveTrackingScreen(orderId: orderId),
        ),
      );
    } else if (screen == 'assigned_orders' && orderId != null) {
      // Navigate Rider to Assigned Orders Screen
      // navigatorKey.currentState?.push(
      //   MaterialPageRoute(
      //     builder: (_) => RiderAssignedOrdersScreen(targetOrderId: orderId),
      //   ),
      // );
    } else if (screen == 'order_history') {
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => const OrderHistoryScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CartProvider()),
        ChangeNotifierProvider(create: (_) => RiderController()),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey, // Attached global key for navigation
        debugShowCheckedModeBanner: false,
        home: const GlobalFeedbackListener(
          child: AuthWrapper(),
        ),
      ),
    );
  }
}