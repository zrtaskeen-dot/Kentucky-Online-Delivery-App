import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'forgot_password.dart';
import 'rider/rider_home_screen.dart';
import 'main_navigation.dart';
import 'signup_screen.dart';
import 'fcm_service.dart'; // 👈 ADDED

class LoginScreen extends StatefulWidget {
  final String role;
  final bool allowSignup;
  final bool skipFirestoreCheck;

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
  bool _obscurePassword = true;

  // ── Theme (matches the rest of the app, incl. SignUpScreen) ──
  static const Color bgColor = Color(0xFFFCF8DD);
  static const Color themeColor = Color(0xFFA70000);
  static const Color creamColor = Color(0xFFFEF9E7);
  static const Color fieldColor = Color(0xFFFFFFF0);

  // Mirrors SignUpScreen.roleMap — needed here because the Firestore user
  // document for an email/password sign-up is now created on first
  // verified login (below), not at sign-up time.
  static const Map<String, String> roleMap = {
    'customer': 'R001',
    'rider': 'R002',
    'admin': 'R003',
  };

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Default snackbar background now matches the app's maroon theme
  // instead of the previous red, so error/info messages look
  // consistent with the rest of the UI.
  void _showSnack(String msg, {Color color = themeColor}) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  // ────────────────────────────────────────────────────────────
  // 👈 ADDED: small helper to write to both log collections at once
  // ────────────────────────────────────────────────────────────
  Future<void> _logActivity({
    required String action,
    required String performedBy,
    required String role,
    required String branch,
    required String details,
  }) async {
    try {
      final payload = {
        'action': action,
        'performed_by': performedBy,
        'role': role,
        'branch': branch,
        'details': details,
        'created_at': FieldValue.serverTimestamp(),
      };
      await FirebaseFirestore.instance.collection("system_log").add(payload);
      await FirebaseFirestore.instance.collection("activity_logs").add(payload);
    } catch (e) {
      // Logging failure should never block login flow.
      debugPrint('Activity log failed: $e');
    }
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

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    final prevUser = FirebaseAuth.instance.currentUser;
    final String? guestUid = (prevUser != null && prevUser.isAnonymous)
        ? prevUser.uid
        : null;

    try {
      // Before attempting a password sign-in, find out how this email is
      // actually registered with Firebase Auth — no account, a Google
      // account, or a real password account — so someone who signed up
      // with Google (and so never set a password) gets told to use the
      // Google button instead of a confusing "wrong password" error.
      //
      // NOTE: fetchSignInMethodsForEmail() only works when "Email
      // Enumeration Protection" is OFF for this Firebase project
      // (Firebase console → Authentication → Settings → User actions).
      // If that protection is ON, it always returns an empty list
      // regardless of whether the account exists, and every attempt
      // falls through to the normal sign-in call below — Firebase's own
      // error still shows in that case, just without this extra
      // precision.
      final methods = await FirebaseAuth.instance.fetchSignInMethodsForEmail(
        email,
      );

      if (methods.isEmpty) {
        _showSnack("User not found. Please sign up first.");
        return;
      }

      if (methods.contains('google.com') && !methods.contains('password')) {
        _showSnack(
          "This account was registered with Google. Please continue with Google to log in.",
        );
        return;
      }

      final userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);
      final user = userCredential.user!;

      if (!user.emailVerified) {
        await FirebaseAuth.instance.signOut();
        _showSnack("Email not verified. Please check your inbox and verify.");
        return;
      }
      if (guestUid != null) {
        await _migrateGuestCart(guestUid, user.uid);
      }

      if (widget.role == 'rider') {
        final snapshot = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: email)
            .where('role', isEqualTo: 'rider')
            .get();

        if (snapshot.docs.isEmpty) {
          await FirebaseAuth.instance.signOut();
          _showSnack("Rider account not found. Please contact admin.");
          return;
        }

        final riderDoc = snapshot.docs.first;
        final riderId = riderDoc.id;
        final riderData = riderDoc.data();
        final riderName = (riderData['name'] ?? riderData['fullName'] ?? email)
            .toString();
        final branchName = (riderData['branch'] ?? '').toString();

        await FirebaseFirestore.instance
            .collection('users')
            .doc(riderId)
            .update({'emailVerified': true});

        // 👈 ADDED: without this, the FCM token never reaches
        // Firestore, so the backend has nothing to send push
        // notifications to.
        await FcmService.syncDeviceToken(riderId);

        // 👈 ADDED: log rider login
        await _logActivity(
          action: 'Rider Login',
          performedBy: riderName,
          role: 'Rider',
          branch: branchName,
          details: 'Rider "$riderName" logged in — Branch: "$branchName"',
        );

        if (!mounted) return;
        // Clear the ENTIRE back stack (including the Role Selection screen)
        // instead of just replacing this route. pushReplacement left Role
        // Selection (and anything before it) alive underneath, which is
        // what let the back button return to it, and let old screens (with
        // their Firestore listeners/dialogs) stay mounted in the background
        // after switching roles.
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => RiderHomeScreen(riderId: riderId)),
          (route) => false,
        );
      } else {
        final snapshot = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: email)
            .get();

        String customerName = email;

        if (snapshot.docs.isNotEmpty) {
          final userId = snapshot.docs.first.id;
          final userData = snapshot.docs.first.data();
          customerName = (userData['name'] ?? userData['fullName'] ?? email)
              .toString();

          await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .update({'emailVerified': true});
        } else {
          // No Firestore document yet: this is the first login after this
          // person verified the email from an email/password sign-up (the
          // doc is deliberately not created at sign-up time anymore — see
          // SignUpScreen._signUp). We know they're verified at this point
          // (checked above), so it's now safe to create their user doc.
          if (user.displayName != null && user.displayName!.trim().isNotEmpty) {
            customerName = user.displayName!.trim();
          }

          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .set({
                'name': customerName,
                'email': email,
                // 'role' text field removed — roleID is the source of
                // truth now; look up the display name from the
                // 'user_role' collection (doc id == roleID) when needed.
                'roleID': roleMap[widget.role],
                'createdAt': FieldValue.serverTimestamp(),
                'emailVerified': true,
              });
        }

        // 👈 ADDED: save this device's FCM token now that we know
        // who's logged in.
        await FcmService.syncDeviceToken(user.uid);

        // 👈 ADDED: log customer login
        await _logActivity(
          action: 'Customer Login',
          performedBy: customerName,
          role: 'Customer',
          branch: '',
          details: 'Customer "$customerName" logged in to the app',
        );

        if (!mounted) return;
        // Clear the entire back stack so Role Selection / Login can't be
        // reached with the back button, and so this old HomeScreen instance
        // is properly disposed (stops its pending-feedback listener) if the
        // user later logs in as a different role on the same device.
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const MainScreen()),
          (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      String msg = "Login failed. Please try again.";
      if (e.code == 'wrong-password') msg = "Incorrect password.";
      if (e.code == 'user-not-found') msg = "No account found with this email.";
      if (e.code == 'invalid-email') msg = "Invalid email format.";
      if (e.code == 'too-many-requests') msg = "Too many attempts. Wait a bit.";
      if (e.code == 'network-request-failed') {
        msg = "Check internet connection.";
      }
      if (e.code == 'invalid-credential') msg = "Invalid email or password.";
      _showSnack(msg);
    } catch (e) {
      _showSnack("An error occurred: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);

    final prevUser = FirebaseAuth.instance.currentUser;
    final String? guestUid = (prevUser != null && prevUser.isAnonymous)
        ? prevUser.uid
        : null;

    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();

      if (googleUser == null) {
        setState(() => _isLoading = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await FirebaseAuth.instance
          .signInWithCredential(credential);
      final user = userCredential.user;

      if (user != null) {
        final userDoc = FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid);
        final docSnap = await userDoc.get();

        if (!docSnap.exists) {
          // No account for this Google identity — the login page must
          // NOT create one. signInWithCredential() already created the
          // Firebase Auth user though, so sign both of it and the cached
          // Google session back out, or the next "Continue with Google"
          // tap would silently succeed via the still-active session
          // instead of showing the account picker again.
          await FirebaseAuth.instance.signOut();
          await GoogleSignIn().signOut();
          if (!mounted) return;
          _showSnack("User not found. Please sign up first.");
          return;
        }

        if (guestUid != null) {
          await _migrateGuestCart(guestUid, user.uid);
        }

        await userDoc.update({'emailVerified': true});

        // 👈 ADDED
        await FcmService.syncDeviceToken(user.uid);

        // 👈 ADDED: log customer login (google)
        final googleName = (user.displayName ?? user.email ?? '').toString();
        await _logActivity(
          action: 'Customer Login',
          performedBy: googleName,
          role: 'Customer',
          branch: '',
          details: 'Customer "$googleName" logged in to the app (Google)',
        );

        if (!mounted) return;
        // Same fix as email login: clear the whole stack, don't just
        // replace the current route.
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const MainScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      _showSnack("Google Sign-In failed: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isRider = widget.role == "rider";

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(context, isRider),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      _buildField(
                        controller: _emailController,
                        label: 'Email',
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) => v == null || !v.contains('@')
                            ? 'Enter valid email'
                            : null,
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
                        validator: (v) => v != null && v.length < 6
                            ? 'Min 6 characters'
                            : null,
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ForgotPassword(),
                            ),
                          ),
                          child: const Text(
                            "Forgot password?",
                            style: TextStyle(
                              color: themeColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _signIn,
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
                                  "Log In",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),

                      if (!isRider) ...[
                        const SizedBox(height: 24),
                        _buildDivider(),
                        const SizedBox(height: 20),
                        _buildGoogleButton(
                          label: "Continue with Google",
                          onTap: _isLoading ? null : _signInWithGoogle,
                        ),
                      ],

                      if (widget.allowSignup) ...[
                        const SizedBox(height: 28),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              "Don't have an account? ",
                              style: TextStyle(color: Colors.black54),
                            ),
                            TextButton(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      SignUpScreen(role: widget.role),
                                ),
                              ),
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text(
                                "Sign up",
                                style: TextStyle(
                                  color: themeColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],

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

  Widget _buildHeader(BuildContext context, bool isRider) {
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
                      color: Colors.white.withValues(alpha: 0.15),
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
            Text(
              isRider ? 'Rider Login' : 'Welcome Back',
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
                color: creamColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isRider
                  ? 'Log in to start your deliveries'
                  : 'Log in to continue ordering',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                letterSpacing: 0.1,
                color: creamColor.withValues(alpha: 0.85),
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
            color: Colors.black.withValues(alpha: 0.03),
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
        Expanded(child: Divider(color: Colors.black.withValues(alpha: 0.15))),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            "or",
            style: TextStyle(color: Colors.black45, fontSize: 12),
          ),
        ),
        Expanded(child: Divider(color: Colors.black.withValues(alpha: 0.15))),
      ],
    );
  }

  Widget _buildGoogleButton({required String label, VoidCallback? onTap}) {
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
