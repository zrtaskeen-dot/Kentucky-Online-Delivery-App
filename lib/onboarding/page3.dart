import 'package:flutter/material.dart';
import '../login_screen.dart';
import 'package:lottie/lottie.dart';

class OnboardPage3 extends StatelessWidget {
  const OnboardPage3({super.key});

  @override
  Widget build(BuildContext context) {
    double screenHeight = MediaQuery.of(context).size.height;
    double screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      body: Container(
        color: const Color(0xFFFFF5D7),
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 120),

            const Text(
              "WELCOME!",
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),

            const Text(
              "KENTUCKY PROVIDES YOU\nFAST FOOD WITH FAST DELIVERY",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 40),

            // --- CUSTOMER BUTTON ---
            SizedBox(
              width: screenWidth * 0.6,
              child: ElevatedButton(
                onPressed: () {
                  // Direct login screen without Firestore check
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LoginScreen(
                        role: "customer",
                        allowSignup: true,
                        skipFirestoreCheck: true,
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFB22222),
                  foregroundColor: const Color(0xFFFFF5D7),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: const Text("CUSTOMER"),
              ),
            ),
            const SizedBox(height: 20),

            // --- RIDER BUTTON ---
            SizedBox(
              width: screenWidth * 0.6,
              child: ElevatedButton(
                onPressed: () {
                  // Directly go to rider login
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LoginScreen(
                        role: "rider",
                        allowSignup: false,
                        skipFirestoreCheck: true,
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFB22222),
                  foregroundColor: const Color(0xFFFFF5D7),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: const Text("RIDER"),
              ),
            ),

            const Spacer(),

            /// ---------- LOTTIE ANIMATION ----------
            SizedBox(
              height: screenHeight * 0.28,
              width: screenWidth * 0.8,
              child: Lottie.asset(
                "assets/images/burger_anim.json",
                fit: BoxFit.contain,
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}