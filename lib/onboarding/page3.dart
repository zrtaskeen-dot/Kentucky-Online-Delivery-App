import 'package:flutter/material.dart';
import '../login_screen.dart';

class OnboardPage3 extends StatelessWidget {
  const OnboardPage3({super.key});

  // Same brand palette as the rest of the onboarding flow.
  static const primary = Color(0xFFA70000);
  static const maroonDark = Color(0xFF6E0000);
  static const ink = Color(0xFF2B1010);
  static const muted = Color(0xFF8A7370);
  static const warmBg = Color(0xFFFFFDF8);

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: warmBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Small brand mark instead of a plain heading — gives the
                // screen an anchor point before the welcome text.
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [primary, maroonDark],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: primary.withValues(alpha: 0.25),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.restaurant_menu_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
                const SizedBox(height: 28),

                Text(
                  "Welcome to Kentucky",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Fast food, delivered fast.\nTell us who's ordering.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, height: 1.5, color: muted),
                ),
                const SizedBox(height: 40),

                // --- CUSTOMER — primary action, filled ---
                SizedBox(
                  width: screenWidth * 0.68,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LoginScreen(
                            role: "customer",
                            allowSignup: true,
                            skipFirestoreCheck: true,
                          ),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: const Text(
                      "CUSTOMER",
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // --- RIDER — secondary action, outlined so it doesn't
                // compete with the primary customer path ---
                SizedBox(
                  width: screenWidth * 0.68,
                  height: 54,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LoginScreen(
                            role: "rider",
                            allowSignup: false,
                            skipFirestoreCheck: true,
                          ),
                        ),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primary,
                      side: const BorderSide(color: primary, width: 1.4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: const Text(
                      "RIDER",
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}