import 'package:flutter/material.dart';

class OnboardPage1 extends StatelessWidget {
  const OnboardPage1({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Color(0xFFFFF5D7),
      child: Stack(
        children: [
          // --- Text Column with border & padding ---
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 200,
              ), // moved down
              child: Container(
                padding: const EdgeInsets.all(20), // inner spacing
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(
                    0.8,
                  ), // optional light background
                  borderRadius: BorderRadius.circular(15), // rounded corners
                  border: Border.all(color: Colors.orange, width: 2), // border
                ),
                child: const Text(
                  "PLAN YOUR CRAVINGS\nSCHEDULE YOUR MEAL\nFOR LATER",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22, // bigger text
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),

          // --- Bottom-right half-hidden pizza image ---
          Positioned(
            bottom: -50, // negative hides half
            right: -50,
            child: Image.network(
              "https://res.cloudinary.com/dqjqkwwwh/image/upload/v1765083671/pizza1_lrqaal.png",
              width: 250,
              fit: BoxFit.cover,
            ),
          ),
        ],
      ),
    );
  }
}
