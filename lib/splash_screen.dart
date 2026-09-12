import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'onboarding/page3.dart';
import 'main_navigation.dart'; // Adjust path based on your folder structure

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  static const maroon = Color(0xFFA70000);
  static const maroonDark = Color(0xFF6E0000);
  static const cream = Color(0xFFFCF8DD);
  static const ivory = Color(0xFFFFFFF0);
  static const gold = Color(0xFFFFC107);

  late final AnimationController _controller;
  late final AnimationController _dotsController;

  late final Animation<double> _bgFade;
  late final Animation<double> _glowFade;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _foldSize;
  late final Animation<Offset> _titleSlide;
  late final Animation<double> _titleFade;
  late final Animation<double> _dotsFade;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );

    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    _bgFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.3, curve: Curves.easeOut),
      ),
    );

    _glowFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.05, 0.45, curve: Curves.easeOut),
      ),
    );

    _logoScale = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.45, curve: Curves.elasticOut),
      ),
    );

    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.25, curve: Curves.easeIn),
      ),
    );

    _foldSize = Tween<double>(begin: 0.0, end: 30.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.25, 0.55, curve: Curves.easeOutBack),
      ),
    );

    _titleSlide = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.4, 0.7, curve: Curves.easeOutCubic),
          ),
        );

    _titleFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.4, 0.7, curve: Curves.easeIn),
      ),
    );

    _dotsFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.6, 0.85, curve: Curves.easeIn),
      ),
    );

    _controller.forward();

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        Future.delayed(const Duration(milliseconds: 450), () {
          if (!mounted) return;
          _checkUserAuthAndNavigate();
        });
      }
    });
  }

  // --- Auth status check logic ---
  Future<void> _checkUserAuthAndNavigate() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      try {
        // Firestore se user ka status aur role check kar rahe hain
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (userDoc.exists) {
          final String role = userDoc.data()?['role'] ?? 'customer';

          if (!mounted) return;

          if (role == 'rider') {
            // Agar rider screen alag hai to yahan Rider Dashboard navigate karein
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const MainScreen()),
            );
          } else {
            // Customer logged in -> Direct Main/Home Screen
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const MainScreen()),
            );
          }
          return;
        }
      } catch (e) {
        print("Error checking user role: $e");
      }
    }

    // Agar User Logged in nahi hai to Role Selection screen (OnboardPage3) par bhejen
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, animation, __) =>
            FadeTransition(opacity: animation, child: const OnboardPage3()),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _dotsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: maroon,
      body: Stack(
        children: [
          FadeTransition(
            opacity: _bgFade,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [maroon, maroonDark],
                ),
              ),
            ),
          ),
          FadeTransition(
            opacity: _glowFade,
            child: Stack(
              children: [
                Positioned(
                  top: -70,
                  left: -60,
                  child: _glowCircle(220, cream.withOpacity(0.10)),
                ),
                Positioned(
                  bottom: -90,
                  right: -70,
                  child: _glowCircle(260, gold.withOpacity(0.14)),
                ),
              ],
            ),
          ),
          Center(
            child: AnimatedBuilder(
              animation: Listenable.merge([_controller, _dotsController]),
              builder: (context, child) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Opacity(
                      opacity: _logoFade.value,
                      child: Transform.scale(
                        scale: _logoScale.value,
                        child: _buildLogoCard(),
                      ),
                    ),
                    const SizedBox(height: 30),
                    SlideTransition(
                      position: _titleSlide,
                      child: Opacity(
                        opacity: _titleFade.value,
                        child: const Text(
                          'Kentucky',
                          style: TextStyle(
                            color: cream,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Opacity(
                      opacity: _dotsFade.value,
                      child: _buildLoadingDots(),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _glowCircle(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withOpacity(0.0)]),
      ),
    );
  }

  Widget _buildLoadingDots() {
    return SizedBox(
      height: 10,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final delay = i * 0.2;
          final t = (_dotsController.value - delay) % 1.0;
          final scale = t < 0.5
              ? 0.6 + (t / 0.5) * 0.4
              : 0.6 + ((1.0 - t) / 0.5) * 0.4;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Transform.scale(
              scale: scale,
              child: Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: gold,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildLogoCard() {
    return Container(
      width: 140,
      height: 140,
      decoration: BoxDecoration(
        color: ivory,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.28),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: gold.withOpacity(0.15),
            blurRadius: 30,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Stack(
        children: [
          Center(
            child: Container(
              width: 116,
              height: 116,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [maroon.withOpacity(0.10), maroon.withOpacity(0.02)],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Image.asset(
                  'assets/kentucky_logo.png',
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.restaurant_menu_rounded,
                    color: maroon,
                    size: 80,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: ClipPath(
              clipper: _CornerFoldClipper(),
              child: Container(
                width: _foldSize.value,
                height: _foldSize.value,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      maroon.withOpacity(0.25),
                      maroon.withOpacity(0.08),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CornerFoldClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(size.width, 0);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
