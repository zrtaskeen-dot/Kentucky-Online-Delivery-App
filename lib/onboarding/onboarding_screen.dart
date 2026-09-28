// import 'package:flutter/material.dart';
// import 'page1.dart';
// import 'page2.dart';
// import 'page3.dart';

// class OnboardingScreen extends StatefulWidget {
//   const OnboardingScreen({super.key});

//   @override
//   State<OnboardingScreen> createState() => _OnboardingScreenState();
// }

// class _OnboardingScreenState extends State<OnboardingScreen> {
//   PageController controller = PageController();
//   int currentIndex = 0;

//   List<Widget> pages = [OnboardPage1(), OnboardPage2(), OnboardPage3()];

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       body: Stack(
//         children: [
//           // --- Pages ---
//           PageView(
//             controller: controller,
//             onPageChanged: (i) {
//               setState(() => currentIndex = i);
//             },
//             children: pages,
//           ),

//           // --- TOP SLIDE BAR (3 indicators like image) ---
//           Positioned(
//             top: 100, // moved down from 50 to 100
//             left: 0,
//             right: 0,
//             child: Row(
//               mainAxisAlignment: MainAxisAlignment.center,
//               children: List.generate(
//                 pages.length,
//                 (index) => AnimatedContainer(
//                   duration: Duration(milliseconds: 300),
//                   margin: EdgeInsets.symmetric(
//                     horizontal: 8,
//                   ), // a little more spacing
//                   height: 10, // increased height
//                   width: currentIndex == index
//                       ? 35
//                       : 15, // bigger width for active indicator
//                   decoration: BoxDecoration(
//                     color: currentIndex == index
//                         ? Color(0xFFB22222)
//                         : Colors.grey[300],
//                     borderRadius: BorderRadius.circular(20),
//                   ),
//                 ),
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }
