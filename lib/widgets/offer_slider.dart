import 'package:flutter/material.dart';
import 'dart:async';

class OfferSlider extends StatefulWidget {
  const OfferSlider({super.key});

  @override
  State<OfferSlider> createState() => _OfferSliderState();
}

class _OfferSliderState extends State<OfferSlider> {
  final PageController _controller = PageController();
  int _currentPage = 0;

  // 🧀 Example offers (use your own images)
  final List<Map<String, String>> offers = [
    {
      "title": "🔥 20% Off Chicken Tikka Pizza!",
      "image": "assets/images/offer1.png",
    },
    {
      "title": "🍕 Buy 1 Get 1 Free on Fajita Pizza!",
      "image": "assets/images/offer2.png",
    },
    {
      "title": "🎉 Super Supreme Combo Deal!",
      "image": "assets/images/offer3.png",
    },


  ];

  @override
  void initState() {
    super.initState();
    // Auto slide every 3 seconds
    Timer.periodic(const Duration(seconds: 3), (Timer timer) {
      if (_currentPage < offers.length - 1) {
        _currentPage++;
      } else {
        _currentPage = 0;
      }
      _controller.animateToPage(
        _currentPage,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 150,
      child: PageView.builder(
        controller: _controller,
        itemCount: offers.length,
        itemBuilder: (context, index) {
          final offer = offers[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              decoration: BoxDecoration(
                color: const Color(0xFFA70000),

                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFCF800).withOpacity(0.3),

                    blurRadius: 6,
                    offset: const Offset(3, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Offer Text
                  Expanded(
                    flex: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        offer["title"]!,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Color(0xFFFCF8dd),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                  // Offer Image
                  Expanded(
                    flex: 2,
                    child: Image.asset(offer["image"]!, fit: BoxFit.contain),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
