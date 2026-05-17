import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_signin_button/flutter_signin_button.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'signup_screen.dart';
import 'home_screen.dart';
import 'rider/RiderHomeScreen.dart';
import 'forgot_password.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class LoginScreen extends StatefulWidget {
  final String role;
  final bool allowSignup;
  final bool skipFirestoreCheck; // new flag

  const LoginScreen({
    super.key,
    required this.role,
    required this.allowSignup,
    this.skipFirestoreCheck = false,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  GoogleSignIn? _googleSignIn;

  @override
  void initState() {
    super.initState();

    // Initialize Google Sign-In only for customers
    if (widget.role == "customer") {
      _googleSignIn = kIsWeb
          ? GoogleSignIn(
              clientId: "YOUR_WEB_CLIENT_ID.apps.googleusercontent.com",
            )
          : GoogleSignIn();
    }
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      await _auth.currentUser!.reload();
      final user = _auth.currentUser!;

      if (!user.emailVerified) {
        await _auth.signOut();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Please verify your email before logging in."),
          ),
        );
        return;
      }

      // ✅ Skip Firestore if onboarding
      if (widget.skipFirestoreCheck) {
        if (widget.role == "customer") {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        } else if (widget.role == "rider") {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const RiderHomeScreen()),
          );
        }
        return;
      }

      // 🔥 Firestore check (safe for web)
      final uid = user.uid;
      final userDoc = await _firestore.collection('users').doc(uid).get();
      if (!userDoc.exists) throw Exception("User not found");

      final data = Map<String, dynamic>.from(userDoc.data()!);

      final roleID = data['roleID'] ?? '';
      if (widget.role == "rider" && roleID != "R002") {
        throw Exception("You are not a Rider");
      }
      if (widget.role == "customer" && roleID != "R001") {
        throw Exception("You are not a Customer");
      }

      if (roleID == 'R001') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      } else if (roleID == 'R002') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const RiderHomeScreen()),
        );
      }
    } on FirebaseAuthException catch (e) {
      String message = "Login failed";
      if (e.code == 'user-not-found') {
        message = "No account found with this email";
      } else if (e.code == 'wrong-password')
        message = "Incorrect password";
      else if (e.code == 'invalid-email')
        message = "Invalid email format";

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      // Works on Web too
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> signInWithGoogle() async {
    if (_googleSignIn == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Google login not allowed")));
      return;
    }

    try {
      final googleUser = await _googleSignIn!.signIn();
      if (googleUser == null) return;

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user!;

      // Firestore save (customer only)
      final userRef = _firestore.collection('users').doc(user.uid);
      final snapshot = await userRef.get();
      if (!snapshot.exists) {
        await userRef.set({
          'name': user.displayName ?? 'User',
          'email': user.email,
          'roleID': 'R001',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } catch (e) {
      print("GOOGLE ERROR: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Google Sign-In failed")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEEF2F7),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Login',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 40),

                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    labelText: 'Email',
                  ),
                  validator: (value) => value == null || !value.contains('@')
                      ? 'Enter valid email'
                      : null,
                ),
                const SizedBox(height: 20),

                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    labelText: 'Password',
                  ),
                  validator: (value) => value != null && value.length < 6
                      ? 'Min 6 characters'
                      : null,
                ),

                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ForgotPassword()),
                    ),
                    child: const Text("Forgot password?"),
                  ),
                ),

                const SizedBox(height: 10),

                ElevatedButton(
                  onPressed: _isLoading ? null : _signIn,
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text("Log In"),
                ),

                const SizedBox(height: 20),

                if (widget.role == "customer")
                  SignInButton(
                    Buttons.Google,
                    text: "Sign in with Google",
                    onPressed: _isLoading ? null : signInWithGoogle,
                  ),

                const SizedBox(height: 20),

                if (widget.allowSignup)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("Don’t have an account? "),
                      TextButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SignUpScreen(role: widget.role),
                          ),
                        ),
                        child: const Text("Sign up"),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
