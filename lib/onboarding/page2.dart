import 'package:flutter/material.dart';

class OnboardPage2 extends StatelessWidget {
  const OnboardPage2({super.key});

  @override
  Widget build(BuildContext context) {
    double screenHeight = MediaQuery.of(context).size.height;
    double screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      body: Stack(
        children: [
          Container(color: Color(0xFFFFF5D7)),
          // First image (main) - smaller size
          Align(
            alignment: Alignment.bottomCenter,
            child: Image.network(
              "https://res.cloudinary.com/dqjqkwwwh/image/upload/v1765097750/Untitled_428_x_926_px_512_x_640_px_1_zvq0td.png",
              width: screenWidth * 0.6, // reduce width to 60% of screen
              height: screenHeight * 0.4, // reduce height to 40% of screen
              fit: BoxFit.contain,
            ),
          ),
          // Second image (partially hidden on left)
          Positioned(
            left: -screenWidth * 0.15, // partially hide on left
            top: screenHeight * 0.35, // adjust vertically
            child: Image.network(
              "https://res.cloudinary.com/dqjqkwwwh/image/upload/v1765098125/Untitled_428_x_926_px_512_x_640_px_2_uglsp2.png",
              width: screenWidth * 0.3, // smaller image
              height: screenHeight * 0.2,
              fit: BoxFit.contain,
            ),
          ),
          // Text and arrow
          Column(
            children: [
              SizedBox(height: 120),
              const Center(
                child: Text(
                  "TRACK YOUR ORDER",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Spacer(),
              Align(
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: IconButton(
                    icon: Icon(Icons.arrow_forward, size: 30),
                    onPressed: () {
                      // navigate to next page
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
