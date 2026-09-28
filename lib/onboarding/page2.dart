import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'page3.dart';

class OnboardPage2 extends StatelessWidget {
  const OnboardPage2({super.key});

  static const primary = Color(0xFFA70000);
  static const accentOrange = Color(0xFFFF8A00);
  static const ink = Color(0xFF2B1010);
  static const muted = Color(0xFF8A7370);
  static const warmBg = Color(0xFFFFFDF8);

  static const String onboardingSeenKey = 'has_seen_onboarding';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: warmBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Progress bar + Skip
              Row(
                children: [
                  Expanded(child: _buildOnboardProgressBar(1)),
                  const SizedBox(width: 16),
                  TextButton(
                    onPressed: () =>
                        _skipOnboardingTo(context, const OnboardPage3()),
                    style: TextButton.styleFrom(
                      foregroundColor: muted,
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      "Skip",
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 36),

              RichText(
                text: const TextSpan(
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                    letterSpacing: -0.5,
                  ),
                  children: [
                    TextSpan(
                      text: "Track your order,\n",
                      style: TextStyle(color: ink),
                    ),
                    TextSpan(
                      text: "live to your door",
                      style: TextStyle(color: primary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                "Follow every step from the kitchen to your doorstep, "
                "in real time.",
                style: TextStyle(fontSize: 14, height: 1.5, color: muted),
              ),
              const SizedBox(height: 18),

              _buildOnboardChip(
                icon: Icons.location_on_rounded,
                text: "Live rider location on the map",
              ),

              const SizedBox(height: 8),
              Expanded(
                child: _buildOnboardHero(
                  imageUrl:
                      "https://res.cloudinary.com/dqjqkwwwh/image/upload/v1765097750/Untitled_428_x_926_px_512_x_640_px_1_zvq0td.png",
                  badges: [
                    Positioned(
                      left: 4,
                      top: 20,
                      child: _buildOnboardIconBadge(
                        icon: Icons.delivery_dining_rounded,
                        bg: accentOrange,
                        iconColor: Colors.white,
                      ),
                    ),
                    Positioned(
                      right: 4,
                      bottom: 28,
                      child: _buildOnboardIconBadge(
                        icon: Icons.check_circle_rounded,
                        bg: Colors.white,
                        iconColor: primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () =>
                      _skipOnboardingTo(context, const OnboardPage3()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentOrange,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Get Started",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward_rounded, size: 20),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shared onboarding pieces (local copy — see page1.dart) ──────────

const _onboardPrimary = Color(0xFFA70000);
const _onboardOrange = Color(0xFFFF8A00);

Future<void> _skipOnboardingTo(BuildContext context, Widget page) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('has_seen_onboarding', true);
  if (!context.mounted) return;
  Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => page));
}

Widget _buildOnboardProgressBar(int activeIndex) {
  return Row(
    children: List.generate(3, (i) {
      return Expanded(
        child: Container(
          height: 4,
          margin: EdgeInsets.only(right: i == 2 ? 0 : 6),
          decoration: BoxDecoration(
            color: i == activeIndex
                ? _onboardOrange
                : _onboardPrimary.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      );
    }),
  );
}

Widget _buildOnboardChip({required IconData icon, required String text}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: _onboardOrange.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: _onboardOrange),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _onboardPrimary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

Widget _buildOnboardIconBadge({
  required IconData icon,
  required Color bg,
  required Color iconColor,
  double size = 44,
}) {
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: bg,
      shape: BoxShape.circle,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.12),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Icon(icon, color: iconColor, size: size * 0.45),
  );
}

Widget _buildOnboardHero({
  required String imageUrl,
  required List<Widget> badges,
}) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final double side = math.min(constraints.maxWidth, constraints.maxHeight);
      final double imageSize = side * 0.66;
      final double ring1 = side * 0.78;
      final double ring2 = side * 0.92;

      return Center(
        child: SizedBox(
          width: side,
          height: side,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size(ring2, ring2),
                painter: _DashedCirclePainter(
                  color: _onboardOrange.withValues(alpha: 0.18),
                ),
              ),
              CustomPaint(
                size: Size(ring1, ring1),
                painter: _DashedCirclePainter(
                  color: _onboardPrimary.withValues(alpha: 0.22),
                ),
              ),
              Container(
                width: imageSize,
                height: imageSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _onboardPrimary.withValues(alpha: 0.18),
                      blurRadius: 30,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: ClipOval(
                  // 👈 FIX: same as page1.dart — BoxFit.cover was
                  // cropping the image; BoxFit.contain shows it fully.
                  child: Image.network(imageUrl, fit: BoxFit.contain),
                ),
              ),
              ...badges,
            ],
          ),
        ),
      );
    },
  );
}

class _DashedCirclePainter extends CustomPainter {
  final Color color;
  _DashedCirclePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const dashCount = 46;
    for (int i = 0; i < dashCount; i++) {
      final startAngle = i * 2 * math.pi / dashCount;
      const sweep = (2 * math.pi / dashCount) * 0.5;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweep,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DashedCirclePainter oldDelegate) =>
      oldDelegate.color != color;
}