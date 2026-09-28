import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'forgot_password.dart';
import 'rider/rider_home_screen.dart';
import 'main_navigation.dart';
import 'signup_screen.dart';
import 'fcm_service.dart';

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

  static const Color bgColor = Colors.white;
  static const Color themeColor = Color(0xFFA70000); // Maroon (same as Home)
  static const Color creamColor = Color(0xFFFEF9E7);
  static const Color fieldColor = Color(0xFFFFFDFA); // same as Home's card tint

  static const Color successBorder = Color(0xFF4A7C59);
  static const Color successBg = Color(0xFFEAF3ED);
  static const Color successText = Color(0xFF2F5B3E);
  static const Color errorBorder = Color(0xFFC62828);
  static const Color errorBg = Color(0xFFFDECEA);
  static const Color errorText = Color(0xFFB71C1C);

  // Maps a role keyword to its doc id in the 'user_role' collection.
  // Keep this in sync with signup_screen.dart's roleMap — 'users'
  // documents store only the roleID (e.g. 'R001'), never the role
  // text itself.
  static const Map<String, String> roleMap = {
    'customer': 'R001',
    'rider': 'R002',
    'admin': 'R003',
  };

  // Looks up the human-readable role name from 'user_role' (doc id ==
  // roleID) whenever the actual text is needed — e.g. for display or
  // logging. Falls back to an empty string if the lookup fails.
  Future<String> _fetchRoleName(String roleID) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('user_role')
          .doc(roleID)
          .get();
      return (doc.data()?['rolename'] ?? '').toString();
    } catch (e) {
      debugPrint('Failed to fetch role name for $roleID: $e');
      return '';
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showSnack(String msg, {bool isError = true}) {
    if (!mounted) return;
    final borderColor = isError ? errorBorder : successBorder;
    final fillColor = isError ? errorBg : successBg;
    final textColor = isError ? errorText : successText;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: EdgeInsets.zero,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor, width: 1.2),
          ),
          child: Text(
            msg,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
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
      final userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);
      final user = userCredential.user!;

      if (!user.emailVerified) {
        await FirebaseAuth.instance.signOut();
        _showSnack("Email not verified. Please check your inbox.");
        return;
      }

      if (guestUid != null) {
        await _migrateGuestCart(guestUid, user.uid);
      }

      if (widget.role == 'rider') {
        // Looking the account up by the signed-in user's own uid (instead
        // of a Firestore query on the 'email' + 'roleID' fields) fixes
        // two real ways a rider whose account genuinely exists could get
        // "Rider account not found": (1) the stored 'email' field having
        // different casing than what they just typed — Firebase Auth
        // itself is case-insensitive so sign-in succeeds, but an exact
        // Firestore string match on 'email' then silently misses; and
        // (2) riders created through an older admin flow that only ever
        // set a legacy 'role' text field, never the newer 'roleID' this
        // query required. Fetching by uid can't miss on casing, and we
        // check both the current 'roleID' and that legacy 'role' field.
        DocumentSnapshot<Map<String, dynamic>> riderDoc;
        try {
          riderDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();
        } catch (e) {
          await FirebaseAuth.instance.signOut();
          _showSnack("Could not verify your account. Please try again.");
          return;
        }

        final riderData = riderDoc.data();
        final roleID = (riderData?['roleID'] ?? '').toString();
        final legacyRole = (riderData?['role'] ?? '').toString().toLowerCase();
        final isRider = roleID == roleMap['rider'] || legacyRole == 'rider';

        if (riderData == null || !isRider) {
          await FirebaseAuth.instance.signOut();
          _showSnack("Rider account not found. Please contact admin.");
          return;
        }

        final riderId = riderDoc.id;
        final riderName = (riderData['name'] ?? riderData['fullName'] ?? email)
            .toString();
        final branchName = (riderData['branch'] ?? '').toString();

        // 👈 ADDED: block-check — admin ne is rider ko block kiya ho to
        // login yahin rok dein.
        final riderStatus = (riderData['status'] ?? 'active').toString();
        if (riderStatus == 'blocked') {
          await FirebaseAuth.instance.signOut();
          _showSnack(
            "Your account has been blocked by admin. Contact support.",
          );
          return;
        }

        await FirebaseFirestore.instance
            .collection('users')
            .doc(riderId)
            .update({'emailVerified': true});

        await FcmService.syncDeviceToken(riderId);

        //  rider login
        await _logActivity(
          action: 'Rider Login',
          performedBy: riderName,
          role: 'Rider',
          branch: branchName,
          details: 'Rider "$riderName" logged in — Branch: "$branchName"',
        );

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => RiderHomeScreen(riderId: riderId)),
        );
      } else {
        DocumentSnapshot<Map<String, dynamic>> userDoc;
        try {
          userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();
        } catch (e) {
          await FirebaseAuth.instance.signOut();
          _showSnack("Could not verify your account. Please try again.");
          return;
        }

        if (!userDoc.exists) {
          await FirebaseAuth.instance.signOut();
          _showSnack("Account not found. Please contact admin.");
          return;
        }

        final userId = userDoc.id;
        final userData = userDoc.data()!;
        final customerName = (userData['name'] ?? userData['fullName'] ?? email)
            .toString();

        final userStatus = (userData['status'] ?? 'active').toString();
        if (userStatus == 'blocked') {
          await FirebaseAuth.instance.signOut();
          _showSnack(
            "Your account has been blocked by admin. Contact support.",
          );
          return;
        }

        await FirebaseFirestore.instance.collection('users').doc(userId).update(
          {'emailVerified': true},
        );

        // 👈 ADDED: save this device's FCM token now that we know
        // who's logged in.
        await FcmService.syncDeviceToken(user.uid);

        // 👈 ADDED: log customer login
        await _logActivity(
          action: 'Customer Login',
          performedBy: customerName,
          role: widget.role == 'owner' ? 'Owner' : 'Customer',
          branch: '',
          details:
              '${widget.role == 'owner' ? 'Owner' : 'Customer'} "$customerName" logged in to the app',
        );

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MainScreen()),
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
        if (guestUid != null) {
          await _migrateGuestCart(guestUid, user.uid);
        }

        final userDoc = FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid);
        final docSnap = await userDoc.get();

        if (!docSnap.exists) {
          await userDoc.set({
            'name': user.displayName ?? '',
            'email': user.email ?? '',
            // roleID is the source of truth — look up the display
            // name from 'user_role' (doc id == roleID) via
            // _fetchRoleName whenever the role text itself is needed.
            'roleID': roleMap['customer'],
            'createdAt': FieldValue.serverTimestamp(),
            'emailVerified': true,
          });
        } else {
          await userDoc.update({'emailVerified': true});
        }

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
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MainScreen()),
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
            colors: [themeColor, Color(0xFF7A0000)],
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
