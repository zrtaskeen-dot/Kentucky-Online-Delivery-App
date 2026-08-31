import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// Apni screens yahan import karein
import 'main_navigation.dart'; // Customer ki MainScreen/HomeScreen
import 'onboarding/page3.dart';     // Onboarding / Login Page
import 'rider/RiderHomeScreen.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      // Firebase authStateChanges se real-time check hoga ke user logged in hai ya nahi
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // 1. Jab tak Auth status check ho raha ho:
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFFFF9800)), // App Theme Color
            ),
          );
        }

        // 2. Agar user logged in hai:
        if (snapshot.hasData && snapshot.data != null) {
          final User user = snapshot.data!;

          // User ka role Firestore se check karke sahi screen par bhejein
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

                if (role == 'rider') {
                  return RiderHomeScreen(riderId: user.uid);
                }
              }

              // Default Customer Screen
              return const MainScreen();
            },
          );
        }

        // 3. Agar user logged in nahi hai -> Login/Onboarding screen par bhejein
        return const OnboardPage3();
      },
    );
  }
}