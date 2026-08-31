import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'login_screen.dart';
import 'main_navigation.dart';
import 'rider/RiderHomeScreen.dart';
import 'fcm_service.dart'; // 👈 ADDED

class SignUpScreen extends StatefulWidget {
  final String role; // 'customer' or 'rider'

  const SignUpScreen({super.key, required this.role});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;

  // ── Theme ──
  static const Color bgColor = Color(0xFFF9F0E0);
  static const Color themeColor = Color(0xFFA62600);
  static const Color creamColor = Color(0xFFFEF9E7);
  static const Color fieldColor = Color(0xFFFFFFF0);

  final Map<String, String> roleMap = {
    'customer': 'R001',
    'rider': 'R002',
    'admin': 'R003',
  };

  static final RegExp _emailRegex = RegExp(
    r'^[a-zA-Z0-9.!#$%&*+/=?^_`{|}~-]+@[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)+$',
  );

  String? _validateEmail(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Enter your email';
    if (!_emailRegex.hasMatch(v)) return 'Enter a valid email address';
    return null;
  }

  String? _validatePassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Enter a password';
    if (v.length < 8) return 'At least 8 characters';
    if (!RegExp(r'[A-Z]').hasMatch(v)) return 'Add at least 1 uppercase letter';
    if (!RegExp(r'[a-z]').hasMatch(v)) return 'Add at least 1 lowercase letter';
    if (!RegExp(r'[0-9]').hasMatch(v)) return 'Add at least 1 number';
    if (!RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=\[\]\\/~`]').hasMatch(v)) {
      return 'Add at least 1 special character';
    }
    return null;
  }

  // Small helper so every snackbar in this screen consistently uses the
  // app's maroon theme color instead of the default red.
  void _showSnack(String msg, {Color color = themeColor}) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  // ────────────────────────────────────────────────────────────
  // GUEST FLOW — anonymous Firebase login + cart migration
  // ────────────────────────────────────────────────────────────

  Future<void> _continueAsGuest() async {
    setState(() => _isLoading = true);
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const MainScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      _showSnack("Could not continue as guest: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _migrateGuestCart(String guestUid, String newUid) async {
    if (guestUid == newUid) return;
    try {
      final guestCartSnap = await FirebaseFirestore.instance
          .collection('carts')
          .where('userId', isEqualTo: guestUid)
          .get();

      for (final doc in guestCartSnap.docs) {
        final data = Map<String, dynamic>.from(doc.data());
        data['userId'] = newUid;
        await FirebaseFirestore.instance.collection('carts').add(data);
        await doc.reference.delete();
      }
    } catch (e) {
      debugPrint('Guest cart migration failed: $e');
    }
  }

  Widget _buildGuestButton() {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Center(
        child: TextButton(
          onPressed: _isLoading ? null : _continueAsGuest,
          style: TextButton.styleFrom(padding: EdgeInsets.zero),
          child: const Text(
            "Continue as Guest",
            style: TextStyle(
              color: themeColor,
              fontWeight: FontWeight.w700,
              fontSize: 14,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final prevUser = FirebaseAuth.instance.currentUser;
    final String? guestUid =
        (prevUser != null && prevUser.isAnonymous) ? prevUser.uid : null;

    try {
      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
          );

      await credential.user!.sendEmailVerification();
      await credential.user!.updateDisplayName(_nameController.text.trim());

      await FirebaseFirestore.instance
          .collection('users')
          .doc(credential.user!.uid)
          .set({
            'name': _nameController.text.trim(),
            'email': _emailController.text.trim(),
            'roleID': roleMap[widget.role],
            'isEmailVerified': false,
          });

      if (guestUid != null) {
        await _migrateGuestCart(guestUid, credential.user!.uid);
      }

      // 👈 ADDED: save this device's FCM token right after account
      // creation, same as the login flow.
      await FcmService.syncDeviceToken(credential.user!.uid);

      if (!mounted) return;
      _showSnack("Verification email sent. Please check your email.");

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => LoginScreen(role: widget.role, allowSignup: true),
        ),
      );
    } on FirebaseAuthException catch (e) {
      _showSnack(e.message ?? 'Registration failed');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String? _pendingGuestUidForGoogle;

  Future<UserCredential?> signUpWithGoogle() async {
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn(
        serverClientId:
            '848662087857-4ht9ticbmr7p6fpmju63spi06lnn652n.apps.googleusercontent.com',
      );

      try {
        await googleSignIn.signOut();
      } catch (_) {}

      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) return null;

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await FirebaseAuth.instance.signInWithCredential(
        credential,
      );

      final user = userCredential.user;
      if (user != null) {
        if (_pendingGuestUidForGoogle != null) {
          await _migrateGuestCart(_pendingGuestUidForGoogle!, user.uid);
          _pendingGuestUidForGoogle = null;
        }

        final userDoc = FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid);
        final snapshot = await userDoc.get();

        if (!snapshot.exists) {
          await userDoc.set({
            'name': user.displayName ?? 'User',
            'email': user.email,
            'photoUrl': user.photoURL,
            'roleID': roleMap[widget.role],
          });
        }

        // 👈 ADDED
        await FcmService.syncDeviceToken(user.uid);
      }

      return userCredential;
    } catch (e) {
      if (mounted) {
        _showSnack("Google Sign-Up failed: $e");
      }
      return null;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(context),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                child: Form(
                  key: _formKey,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  child: Column(
                    children: [
                      _buildField(
                        controller: _nameController,
                        label: 'Full Name',
                        icon: Icons.person_outline,
                        validator: (v) =>
                            v!.isEmpty ? 'Enter your full name' : null,
                      ),
                      const SizedBox(height: 16),
                      _buildField(
                        controller: _emailController,
                        label: 'Email',
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                        validator: _validateEmail,
                      ),
                      const SizedBox(height: 16),
                      _buildField(
                        controller: _passwordController,
                        label: 'Password',
                        icon: Icons.lock_outline,
                        obscureText: _obscurePassword,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: Colors.black45,
                            size: 20,
                          ),
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                        ),
                        validator: _validatePassword,
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            'Min 8 characters, with uppercase, lowercase, '
                            'number & special character',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _signUp,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: themeColor,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Text(
                                  "Sign Up",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),

                      const SizedBox(height: 24),
                      _buildDivider(),
                      const SizedBox(height: 20),

                      _buildGoogleButton(
                        label: "Sign up with Google",
                        onTap: _isLoading
                            ? () {}
                            : () async {
                                setState(() => _isLoading = true);

                                final prevUser =
                                    FirebaseAuth.instance.currentUser;
                                _pendingGuestUidForGoogle =
                                    (prevUser != null && prevUser.isAnonymous)
                                        ? prevUser.uid
                                        : null;

                                final userCredential = await signUpWithGoogle();
                                setState(() => _isLoading = false);

                                if (userCredential != null) {
                                  final uid = userCredential.user!.uid;
                                  final userDoc = await FirebaseFirestore
                                      .instance
                                      .collection('users')
                                      .doc(uid)
                                      .get();
                                  final roleID = userDoc['roleID'];

                                  if (!mounted) return;

                                  if (roleID == 'R001') {
                                    Navigator.pushReplacement(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const MainScreen(),
                                      ),
                                    );
                                  } else if (roleID == 'R002') {
                                    Navigator.pushReplacement(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            RiderHomeScreen(riderId: uid),
                                      ),
                                    );
                                  }
                                }
                              },
                      ),

                      const SizedBox(height: 28),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            "Already have an account? ",
                            style: TextStyle(color: Colors.black54),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => LoginScreen(
                                    role: widget.role,
                                    allowSignup: true,
                                  ),
                                ),
                              );
                            },
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text(
                              "Login",
                              style: TextStyle(
                                color: themeColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),

                      // Guest button is hidden for the rider role.
                      if (widget.role != 'rider') _buildGuestButton(),
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

  Widget _buildHeader(BuildContext context) {
    final bool isRider = widget.role == 'rider';
    return ClipPath(
      clipper: _WaveClipper(),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 16,
          bottom: 56,
          left: 24,
          right: 24,
        ),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [themeColor, Color(0xFF7A1A00)],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                InkWell(
                  onTap: () => Navigator.pop(context),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_back_rounded,
                      color: creamColor,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 26),
            const Text(
              'Create Account',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
                color: creamColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isRider
                  ? 'Sign up to start delivering with us'
                  : 'Sign up to start ordering your favorites',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                letterSpacing: 0.1,
                color: creamColor.withOpacity(0.85),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        style: const TextStyle(
          fontWeight: FontWeight.w500,
          color: Colors.black87,
        ),
        validator: validator,
        decoration: InputDecoration(
          filled: true,
          fillColor: fieldColor,
          prefixIcon: Icon(icon, color: themeColor, size: 20),
          suffixIcon: suffixIcon,
          labelText: label,
          labelStyle: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: const BorderSide(color: Colors.black26, width: 1.0),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: const BorderSide(color: Colors.black26, width: 1.0),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: const BorderSide(color: themeColor, width: 1.6),
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Row(
      children: [
        Expanded(child: Divider(color: Colors.black.withOpacity(0.15))),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            "or",
            style: TextStyle(color: Colors.black45, fontSize: 12),
          ),
        ),
        Expanded(child: Divider(color: Colors.black.withOpacity(0.15))),
      ],
    );
  }

  Widget _buildGoogleButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton.icon(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: fieldColor,
          side: const BorderSide(color: Colors.black26),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
        icon: const Icon(
          Icons.g_mobiledata_rounded,
          color: themeColor,
          size: 26,
        ),
        label: Text(
          label,
          style: const TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

class _WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 46);
    path.quadraticBezierTo(
      size.width * 0.25,
      size.height,
      size.width * 0.5,
      size.height - 24,
    );
    path.quadraticBezierTo(
      size.width * 0.75,
      size.height - 48,
      size.width,
      size.height - 10,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}