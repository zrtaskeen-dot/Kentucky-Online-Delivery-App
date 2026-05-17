import 'package:flutter/material.dart';

class SuccessScreen extends StatelessWidget {
  final String? phone; // make nullable

  const SuccessScreen({super.key, this.phone});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(
          "OTP Verified!\n\nPhone: ${phone ?? 'N/A'}",
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
