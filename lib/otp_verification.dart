import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'success_screen.dart';

class OtpVerifyScreen extends StatefulWidget {
  final String verificationId;
  final String phone;

  const OtpVerifyScreen({
    super.key,
    required this.verificationId,
    required this.phone,
  });

  @override
  State<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}

class _OtpVerifyScreenState extends State<OtpVerifyScreen> {
  final TextEditingController otpCtrl = TextEditingController();
  bool loading = false;

  Future<void> verifyOTP() async {
    if (otpCtrl.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter 6-digit OTP")),
      );
      return;
    }

    setState(() => loading = true);

    try {
      // Step 1: Create credential
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: widget.verificationId,
        smsCode: otpCtrl.text.trim(),
      );

      // Step 2: Verify OTP (sign-in temporarily)
      UserCredential userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);

      // Step 3: Store in Firestore (your real goal)
      await FirebaseFirestore.instance
          .collection("customers")
          .doc(widget.phone)
          .set({
        "phone": widget.phone,
        "phoneVerified": true,
        "createdAt": FieldValue.serverTimestamp(),
      });

      // OPTIONAL: Sign out (so user is NOT logged in)
      await FirebaseAuth.instance.signOut();

      // Step 4: Navigate
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => SuccessScreen(phone: widget.phone),
        ),
      );
    } catch (e) {
      print("OTP Error: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: ${e.toString()}")),
      );
    }

    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffFFF7DD),
      appBar: AppBar(
        title: const Text("Verify OTP"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: Padding(
        padding: const EdgeInsets.all(25),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              "Enter the 6-digit OTP sent to:",
              style: TextStyle(fontSize: 18),
            ),
            Text(
              widget.phone,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 25),

            TextField(
              controller: otpCtrl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: InputDecoration(
                hintText: "Enter OTP",
                counterText: "",
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),

            const SizedBox(height: 25),

            SizedBox(
              width: double.infinity,
              height: 45,
              child: ElevatedButton(
                onPressed: loading ? null : verifyOTP,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.brown,
                ),
                child: loading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("Verify"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}