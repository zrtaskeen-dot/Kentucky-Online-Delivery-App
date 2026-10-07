import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'login_screen.dart';
import 'main_navigation.dart';
import 'fcm_service.dart'; // 👈 ADDED

// Capitalizes the first letter of every word as the user types (e.g.
// "ali khan" -> "Ali Khan"), and lower-cases the rest of that word.
// Keeps the cursor exactly where it was.
class CapitalizeWordsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;

    final buffer = StringBuffer();
    bool capitalizeNext = true;

    for (int i = 0; i < newValue.text.length; i++) {
      final ch = newValue.text[i];
      if (ch.trim().isEmpty) {
        buffer.write(ch);
        capitalizeNext = true;
      } else if (capitalizeNext) {
        buffer.write(ch.toUpperCase());
        capitalizeNext = false;
      } else {
        buffer.write(ch.toLowerCase());
      }
    }

    return newValue.copyWith(
      text: buffer.toString(),
      selection: newValue.selection,
    );
  }
}

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
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // ── Theme ──
  static const Color bgColor = Colors.white;
  static const Color themeColor = Color(0xFFA70000);
  static const Color creamColor = Colors.white;
  static const Color fieldColor = Color(0xFFFFFDFA);

  // Success/error message card colors — border, light fill, and text
  // all in the same hue so the card reads as one clear signal.
  static const Color successBorder = Color(0xFF4A7C59);
  static const Color successBg = Color(0xFFEAF3ED);
  static const Color successText = Color(0xFF2F5B3E);
  static const Color errorBorder = Color(0xFFC62828);
  static const Color errorBg = Color(0xFFFDECEA);
  static const Color errorText = Color(0xFFB71C1C);

  final Map<String, String> roleMap = {'customer': 'R001', 'rider': 'R002'};

  // Only @gmail.com addresses are accepted for sign up.
  static final RegExp _emailRegex = RegExp(
    r'^[a-zA-Z0-9.!#$%&*+/=?^_`{|}~-]+@gmail\.com$',
  );

  String? _validateEmail(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Enter your email';
    if (!_emailRegex.hasMatch(v)) {
      return 'Only @gmail.com addresses are allowed';
    }
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

  String? _validateConfirmPassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Confirm your password';
    if (v != _passwordController.text) return 'Passwords do not match';
    return null;
  }

  // Firebase's raw error messages are long, technical, and English-legal
  // sounding (e.g. "The email address is already in use by another
  // account."). This maps the common ones to short, plain messages that
  // fit on a single snackbar line instead of getting cut off.
  String _authErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'This email is already registered. Try logging in.';
      case 'invalid-email':
        return 'That email address looks invalid.';
      case 'weak-password':
        return 'Password is too weak.';
      case 'network-request-failed':
        return 'No internet connection. Please try again.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait and try again.';
      case 'operation-not-allowed':
        return 'Sign up is currently disabled. Try again later.';
      default:
        return 'Registration failed. Please try again.';
    }
  }

  // Success messages get a green-bordered/light-green/green-text card;
  // error messages get the same treatment in red. isError defaults to
  // true since most call sites here are reporting a failure.
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
        duration: const Duration(seconds: 3),
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
            // Was maxLines: 1 with an ellipsis, which cut longer messages
            // off mid-sentence. Messages are now kept short at the
            // source (see _authErrorMessage), and this allows up to 3
            // lines so nothing gets truncated even if one runs long.
            maxLines: 3,
            overflow: TextOverflow.visible,
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
      _showSnack("Could not continue as guest. Please try again.");
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
    final String? guestUid = (prevUser != null && prevUser.isAnonymous)
        ? prevUser.uid
        : null;

    try {
      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
          );

      await credential.user!.sendEmailVerification();
      await credential.user!.updateDisplayName(_nameController.text.trim());

      // 👈 ADDED: save the customer's profile in Firestore (users/{uid}).
      // Before this, only the Auth profile got the name, and Firestore
      // ended up with just fcmToken + emailVerified, so name/email/roleId
      // were missing. merge:true keeps the FCM token write (and the
      // emailVerified update done at login) from overwriting each other.
      await FirebaseFirestore.instance
          .collection('users')
          .doc(credential.user!.uid)
          .set({
            'name': _nameController.text.trim(),
            'email': credential.user!.email ?? _emailController.text.trim(),
            'roleId': roleMap[widget.role],
            'createdAt': FieldValue.serverTimestamp(),
            'emailVerified': false,
          }, SetOptions(merge: true));

      if (guestUid != null) {
        await _migrateGuestCart(guestUid, credential.user!.uid);
      }

      // 👈 ADDED: save this device's FCM token right after account
      // creation, same as the login flow.
      await FcmService.syncDeviceToken(credential.user!.uid);
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;
      _showSnack(
        "Verification email sent. Please verify your email.",
        isError: false,
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => LoginScreen(role: widget.role, allowSignup: true),
        ),
      );
    } on FirebaseAuthException catch (e) {
      _showSnack(_authErrorMessage(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ────────────────────────────────────────────────────────────
  // GOOGLE SIGN-UP — mirror image of the login page's Google flow.

  Future<void> _signUpWithGoogle() async {
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

      if (user == null) return;

      final userDoc = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);
      final docSnap = await userDoc.get();

      if (docSnap.exists) {
        // Already has an account — don't silently log them in from the
        // sign-up screen. Back the Google session out and send them to
        // log in instead.
        await FirebaseAuth.instance.signOut();
        await GoogleSignIn().signOut();
        if (!mounted) return;
        _showSnack("Account already exists. Please log in instead.");
        return;
      }

      await userDoc.set({
        'name': user.displayName ?? '',
        'email': user.email ?? '',
        // ✅ FIXED: Firestore mein field ka asal naam "roleId" hai
        // (chhota d), "roleID" nahi — pehle yeh galat naam likha ja
        // raha tha, isliye login screen (jo roleId check karta hai)
        // is user ko rider/customer tasleem nahi karta tha.
        'roleId': roleMap[widget.role],
        'createdAt': FieldValue.serverTimestamp(),
        // Google already verifies the email address, so there's no
        // separate email-verification step to wait on like there is
        // for the email/password sign-up path above.
        'emailVerified': true,
      });

      if (guestUid != null) {
        await _migrateGuestCart(guestUid, user.uid);
      }

      await FcmService.syncDeviceToken(user.uid);

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const MainScreen()),
        (route) => false,
      );
    } catch (e) {
      _showSnack("Google Sign-Up failed. Please try again.");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
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
                        capitalizeWords: true,
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
                      const SizedBox(height: 16),
                      _buildField(
                        controller: _confirmPasswordController,
                        label: 'Confirm Password',
                        icon: Icons.lock_outline,
                        obscureText: _obscureConfirmPassword,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirmPassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: Colors.black45,
                            size: 20,
                          ),
                          onPressed: () => setState(
                            () => _obscureConfirmPassword =
                                !_obscureConfirmPassword,
                          ),
                        ),
                        validator: _validateConfirmPassword,
                      ),
                      const SizedBox(height: 20),

                      SizedBox(
                        width: 220,
                        height: 50,
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

                      // Google sign-up is a customer-only shortcut, same
                      // as the login page's Google button.
                      if (widget.role != 'rider') ...[
                        const SizedBox(height: 24),
                        _buildDivider(),
                        const SizedBox(height: 20),
                        _buildGoogleButton(
                          label: "Continue with Google",
                          onTap: _isLoading ? null : _signUpWithGoogle,
                        ),
                      ],

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
                color: creamColor.withValues(alpha: 0.85),
              ),
            ),
          ],
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
      width: 220,
      height: 48,
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
            fontSize: 13,
          ),
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
    bool capitalizeWords = false,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      textCapitalization: capitalizeWords
          ? TextCapitalization.words
          : TextCapitalization.none,
      inputFormatters: capitalizeWords ? [CapitalizeWordsFormatter()] : null,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: Colors.black87,
      ),
      validator: validator,
      decoration: InputDecoration(
        filled: true,
        fillColor: fieldColor,
        prefixIcon: Icon(icon, color: themeColor, size: 20),
        suffixIcon: suffixIcon,
        labelText: label,
        labelStyle: const TextStyle(color: Colors.black54, fontSize: 13),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 16,
          horizontal: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.black38),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.black38),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: themeColor, width: 1.6),
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