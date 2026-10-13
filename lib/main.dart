import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'cart_provider.dart';
import 'notification_service.dart';
import 'splash_screen.dart';
import 'global_feedback_listener.dart';
import 'rider/rider_logic.dart';
import 'live_tracking.dart';
import 'order_history.dart';


final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();


@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("Handling a background message: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();

   
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

   
    await NotificationService().initNotifications();

    
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
    
    FirebaseMessaging.instance.getInitialMessage().then((
      RemoteMessage? message,
    ) {
      if (message != null) {
        _handleDeepLink(message.data);
      }
    });

    
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleDeepLink(message.data);
    });
  }

  void _handleDeepLink(Map<String, dynamic> data) {
    final String? screen = data['screen'];
    final String? orderId = data['orderId'];

    if (screen == 'live_tracking' && orderId != null) {
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => LiveTrackingScreen(orderId: orderId)),
      );
    } else if (screen == 'assigned_orders' && orderId != null) {
    
    } else if (screen == 'order_history') {
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const OrderHistoryScreen()),
      );
    } else if (data['type'] == 'new_menu_item') {
     
      final String? menuItemId = data['menuItemId'];
      if (menuItemId != null) {
       
      }
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
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
       
        builder: (context, child) {
          return GlobalFeedbackListener(
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: const SplashScreen(),
      ),
    );
  }
}
