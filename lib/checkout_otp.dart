import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'otp_verification.dart';
import 'package:video_player/video_player.dart';

class PhoneNumberScreen extends StatefulWidget {
  const PhoneNumberScreen({super.key});

  @override
  State<PhoneNumberScreen> createState() => _PhoneNumberScreenState();
}

class _PhoneNumberScreenState extends State<PhoneNumberScreen> {
  final TextEditingController phoneCtrl = TextEditingController();
  final TextEditingController nameCtrl = TextEditingController();
  bool loading = false;

  late VideoPlayerController _videoController;

  @override
  void initState() {
    super.initState();
    _videoController = VideoPlayerController.asset('assets/pizza_animation.mp4')
      ..initialize().then((_) {
        setState(() {});
        _videoController.setLooping(true);
        _videoController.play();
      });
  }

  @override
  void dispose() {
    _videoController.dispose();
    phoneCtrl.dispose();
    nameCtrl.dispose();
    super.dispose();
  }

  String normalizePhoneNumber(String input) {
    String rawPhone = input.trim();
    String formattedPhone;

    if (rawPhone.startsWith("0")) {
      formattedPhone = "+92${rawPhone.substring(1)}";
    } else if (rawPhone.startsWith("92")) {
      formattedPhone = "+$rawPhone";
    } else if (rawPhone.startsWith("+")) {
      formattedPhone = rawPhone;
    } else {
      formattedPhone = "+92$rawPhone"; // fallback
    }

    return formattedPhone;
  }

  Future<void> sendOTP() async {
    if (nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Enter your name")));
      return;
    }

    if (phoneCtrl.text.trim().length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter a valid phone number")),
      );
      return;
    }

    setState(() => loading = true);

    String formattedPhone = normalizePhoneNumber(phoneCtrl.text);

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: formattedPhone,
        verificationCompleted: (_) {},
        verificationFailed: (e) {
          setState(() => loading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message ?? "Verification failed")),
          );
        },
        codeSent: (String verificationId, int? token) {
          setState(() => loading = false);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => OtpVerifyScreen(
                verificationId: verificationId,
                phone: formattedPhone,
              ),
            ),
          );
        },
        codeAutoRetrievalTimeout: (_) {
          setState(() => loading = false);
        },
      );
    } catch (e) {
      setState(() => loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: ${e.toString()}")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffFFF7DD),
      appBar: AppBar(
        title: const Text("Phone Verification"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          children: [
            if (_videoController.value.isInitialized)
              AspectRatio(
                aspectRatio: _videoController.value.aspectRatio,
                child: VideoPlayer(_videoController),
              ),
            const SizedBox(height: 20),
            const Text(
              "Enter Your Name",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                hintText: "Your Name",
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              "Enter Your Phone Number",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                hintText: "03XXXXXXXXX",
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
                onPressed: loading ? null : sendOTP,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.brown),
                child: loading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("Send OTP"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
