// import 'package:flutter/material.dart';
// import 'package:lottie/lottie.dart';
// import 'onboarding/onboarding_screen.dart';

// class SplashScreen extends StatefulWidget {
//   const SplashScreen({super.key});

//   @override
//   State<SplashScreen> createState() => _SplashScreenState();
// }

// class _SplashScreenState extends State<SplashScreen> {
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: Colors.white,

//       body: Center(
//         child: Lottie.asset(
//           'assets/images/splash.json',
//           fit: BoxFit.cover,
//           repeat: false,

//           // 👇 When animation finishes → Next screen
//           onLoaded: (composition) {
//             Future.delayed(composition.duration, () {
//               Navigator.pushReplacement(
//                 context,
//                 MaterialPageRoute(builder: (_) => OnboardingScreen()),
//               );
//             });
//           },
//         ),
//       ),
//     );
//   }
// }
