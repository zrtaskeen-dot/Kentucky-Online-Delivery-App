import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'main_navigation.dart'; 
import 'onboarding/page3.dart';   
import 'rider/rider_home_screen.dart';
import 'global_feedback_listener.dart' show customerHomeReady;

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  
  void _syncCustomerTopicSubscription(String role) {
    const topic = 'all_customers';
    if (role == 'customer') {
      FirebaseMessaging.instance.subscribeToTopic(topic);
    } else {
      FirebaseMessaging.instance.unsubscribeFromTopic(topic);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFFFF9800)), // App Theme Color
            ),
          );
        }

        if (snapshot.hasData && snapshot.data != null) {
          final User user = snapshot.data!;

          return FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
            builder: (context, roleSnapshot) {
              if (roleSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(
                    child: CircularProgressIndicator(color: Color(0xFFFF9800)),
                  ),
                );
              }

              if (roleSnapshot.hasData && roleSnapshot.data!.exists) {
                final data = roleSnapshot.data!.data() as Map<String, dynamic>?;
                final role = data?['role'] ?? 'customer';

                
                _syncCustomerTopicSubscription(role);

                if (role == 'rider') {
                  return RiderHomeScreen(riderId: user.uid);
                }
              }

              return const _HomeReadySignal(child: MainScreen());
            },
          );
        }

        return const OnboardPage3();
      },
    );
  }
}


class _HomeReadySignal extends StatefulWidget {
  final Widget child;
  const _HomeReadySignal({required this.child});

  @override
  State<_HomeReadySignal> createState() => _HomeReadySignalState();
}

class _HomeReadySignalState extends State<_HomeReadySignal> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      customerHomeReady.value = true;
    });
  }

  @override
  void dispose() {
    customerHomeReady.value = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}