import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'rider/rider_auth_repository.dart'; 
import 'login_screen.dart';
import 'main.dart' show navigatorKey;

class AuthController {
  final FirebaseAuth _auth             = FirebaseAuth.instance;
  final RiderAuthRepository _authRepository = RiderAuthRepository();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Email/Password Login
  Future<String> loginWithEmailAndPassword({
    required String email,
    required String password,
    required String expectedRole,
  }) async {
    try {
      // Firebase Authentication Login
      final userCredential = await _auth.signInWithEmailAndPassword(
        email:    email,
        password: password,
      );

      final user = userCredential.user;
      if (user == null) return "Authentication failed.";

      //  Email verification check
      await user.reload();
      if (!user.emailVerified) {
        await _auth.signOut();
        return "Please verify your email before logging in.";
      }

      final userDoc = await _authRepository.getUserDocument(user.uid);
      if (!userDoc.exists || userDoc.data() == null) {
        await _auth.signOut();
        return "User data profile not found in database.";
      }

      final data   = userDoc.data() as Map<String, dynamic>;
      final String roleID = data['roleID'] ?? '';

      if ((data['status'] ?? 'active').toString() == 'blocked') {
        await _auth.signOut();
        return expectedRole == "rider"
            ? "Your account has been blocked by Restaurant."
            : AccountGuard.messageCustomerBlocked;
      }

      if (expectedRole == "customer" && roleID != "R001") {
        await _auth.signOut();
        return "Access Denied: You are not registered as a Customer.";
      }
      if (expectedRole == "rider" && roleID != "R002") {
        await _auth.signOut();
        return "Access Denied: You are not registered as a Rider.";
      }

      if (expectedRole == "rider") {
        await _ensureRiderFields(user.uid, data);
      }

      return "success";
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') return "No account found with this email.";
      if (e.code == 'wrong-password') return "Incorrect password.";
      if (e.code == 'invalid-email')  return "Invalid email format.";
      return e.message ?? "Authentication failed.";
    } catch (e) {
      return e.toString().replaceAll("Exception: ", "");
    }
  }

  
  Future<void> _ensureRiderFields(
      String uid, Map<String, dynamic> existingData) async {
    try {
      final Map<String, dynamic> updates = {};

      
      if (!existingData.containsKey('isAvailable')) {
        updates['isAvailable'] = false;       
      }
      if (!existingData.containsKey('totalOrders')) {
        updates['totalOrders'] = 0;
      }
      if (!existingData.containsKey('delivered')) {
        updates['delivered'] = 0;
      }
      if (!existingData.containsKey('pending')) {
        updates['pending'] = 0;
      }
      if (!existingData.containsKey('statusUpdatedAt')) {
        updates['statusUpdatedAt'] = FieldValue.serverTimestamp();
      }

     
      if (updates.isNotEmpty) {
        await _firestore
            .collection('users')
            .doc(uid)
            .update(updates);
        print("Rider fields auto-added on first login: $uid");
      }
    } catch (e) {
   
      print("_ensureRiderFields error: $e");
    }
  }
}

enum _Revoke { blocked, deleted }

class AccountGuard {
  AccountGuard._();

  static const String messageCustomerBlocked =
      'Your account has been blocked by Restaurant.';
  static const String messageCustomerDeleted =
      'Customer is deleted by Restaurant.';
  static const String messageRiderDeleted =
      'Your account has been deleted by Restaurant.';
  static const String messageRiderBlocked =
      'Your account has been blocked by Restaurant.';

  static const String _kPendingMessage = 'account_guard_pending_message';
  static const String _kPendingRole = 'account_guard_pending_role';
  static const String _kRolePrefix = 'account_guard_role_';

  static StreamSubscription<User?>? _authSub;
  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _docSub;
  static String? _restoredUid;
  static bool _revoking = false;

  static void init() {
    final current = FirebaseAuth.instance.currentUser;
    _restoredUid = (current != null && !current.isAnonymous)
        ? current.uid
        : null;
    _authSub?.cancel();
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_onAuthChanged);
  }

  static Future<String?> consumePendingMessage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final msg = prefs.getString(_kPendingMessage);
      if (msg == null) return null;
      await prefs.remove(_kPendingMessage);
      await prefs.remove(_kPendingRole);
      return msg;
    } catch (_) {
      return null;
    }
  }

  static Future<void> rememberRole(String uid, String role) =>
      _cacheRole(uid, role);

  static Future<bool> ensureActive() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return true;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get(const GetOptions(source: Source.server));
      if (!snap.exists) {
        await _revoke(user.uid, _Revoke.deleted);
        return false;
      }
      if (_isBlocked(snap.data())) {
        await _revoke(user.uid, _Revoke.blocked);
        return false;
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  static bool _isBlocked(Map<String, dynamic>? data) =>
      (data?['status'] ?? 'active').toString().toLowerCase() == 'blocked';

  static String _roleOf(Map<String, dynamic>? data) {
    final id = (data?['roleId'] ?? '').toString();
    final legacy = (data?['role'] ?? '').toString().toLowerCase();
    return (id == 'R002' || legacy == 'rider') ? 'rider' : 'customer';
  }

  static Future<void> _cacheRole(String uid, String role) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_kRolePrefix$uid', role);
    } catch (_) {}
  }

  static Future<String> _cachedRole(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('$_kRolePrefix$uid') ?? 'customer';
    } catch (_) {
      return 'customer';
    }
  }

  static Future<void> _onAuthChanged(User? user) async {
    await _docSub?.cancel();
    _docSub = null;

    if (user == null) {
      _restoredUid = null;
      return;
    }
    if (user.isAnonymous) return;

    _revoking = false;
    final strict = user.uid == _restoredUid;

    if (strict) {
      try {
        await user.reload();
      } on FirebaseAuthException catch (e) {
        if (e.code == 'user-not-found') {
          await _revoke(user.uid, _Revoke.deleted);
          return;
        }
        if (e.code == 'user-disabled') {
          await _revoke(user.uid, _Revoke.blocked);
          return;
        }
      } catch (_) {}
      if (FirebaseAuth.instance.currentUser?.uid != user.uid) return;
    }

    _watch(user.uid, strict);
  }

  static void _watch(String uid, bool strict) {
    var seenExisting = false;
    debugPrint('AccountGuard: watching $uid strict=$strict');
    _docSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((snap) {
          debugPrint(
            'AccountGuard: exists=${snap.exists} '
            'status=${snap.data()?['status']} '
            'cache=${snap.metadata.isFromCache}',
          );
          if (snap.metadata.isFromCache) return;
          if (!snap.exists) {
            if (strict || seenExisting) _revoke(uid, _Revoke.deleted);
            return;
          }
          seenExisting = true;
          final data = snap.data();
          _cacheRole(uid, _roleOf(data));
          if (_isBlocked(data)) _revoke(uid, _Revoke.blocked);
        }, onError: (_) {});
  }

  static Future<void> _revoke(String uid, _Revoke kind) async {
    if (_revoking) return;
    _revoking = true;
    debugPrint('AccountGuard: revoking $uid $kind');

    final role = await _cachedRole(uid);
    final String message;
    if (role == 'rider') {
      message = kind == _Revoke.deleted
          ? messageRiderDeleted
          : messageRiderBlocked;
    } else {
      message = kind == _Revoke.deleted
          ? messageCustomerDeleted
          : messageCustomerBlocked;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPendingMessage, message);
      await prefs.setString(_kPendingRole, role);
    } catch (_) {}

    await _docSub?.cancel();
    _docSub = null;

    try {
      await FirebaseAuth.instance.signOut().timeout(
        const Duration(seconds: 5),
      );
    } catch (_) {}

    _goToLogin(role);
    unawaited(GoogleSignIn().signOut().then((_) {}, onError: (_) {}));
  }

  static NavigatorState? _findNavigator() {
    NavigatorState? found;
    void visit(Element element) {
      if (found != null) return;
      if (element is StatefulElement && element.state is NavigatorState) {
        found = element.state as NavigatorState;
        return;
      }
      element.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
    return found;
  }

  static void _goToLogin(String role, [int attempt = 0]) {
    final nav = navigatorKey.currentState ?? _findNavigator();
    debugPrint('AccountGuard: navigator found=${nav != null}');
    if (nav == null) {
      if (attempt < 50) {
        Timer(const Duration(milliseconds: 200), () {
          _goToLogin(role, attempt + 1);
        });
      }
      return;
    }
    nav.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) =>
            LoginScreen(role: role, allowSignup: role == 'customer'),
      ),
      (route) => false,
    );
  }
}