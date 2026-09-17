// ════════════════════════════════════════════════════════════
// TIER 1 — DATA LAYER (REPOSITORY)
// rider_auth_repository.dart
// ════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class RiderAuthRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final String _cloudinaryCloudName = 'dqjqkwwwh';
  final String _cloudinaryUploadPreset = 'rider_profiles';

  Future<DocumentSnapshot> getUserDocument(String uid) async {
    try {
      return await _firestore
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.serverAndCache));
    } catch (e) {
      debugPrint("Repository Error: $e");
      rethrow;
    }
  }

  Future<void> saveGoogleUserData(
    String uid,
    String name,
    String? email,
  ) async {
    try {
      final userRef = _firestore.collection('users').doc(uid);
      final snapshot = await userRef.get();
      if (!snapshot.exists) {
        await userRef.set({
          'name': name,
          'email': email,
          'roleID': 'R001',
          'createdAt': FieldValue.serverTimestamp(),
          'isAvailable': false,
        });
      }
    } catch (e) {
      debugPrint("Repository Google Save Error: $e");
      rethrow;
    }
  }

  Future<void> saveRiderData({
    required String uid,
    required String name,
    required String phone,
    String? email,
    String? branchId,
  }) async {
    try {
      final userRef = _firestore.collection('users').doc(uid);

      // Guard against silently clobbering an existing account. This used
      // to be an unconditional .set() with no merge and no existence
      // check, so if `uid` ever matched an account that already existed
      // under a different role (e.g. a customer account reused for rider
      // testing), this call would fully replace that document — wiping
      // the customer's own name/email and replacing them with the
      // rider's. That single shared "users/{uid}" doc is exactly why a
      // customer's name can end up showing as the rider's name (and vice
      // versa) even after restarting the app. Rider accounts should use
      // their own dedicated uid, never a uid already in use for another
      // role.
      final existing = await userRef.get();
      if (existing.exists) {
        final existingRole = existing.data()?['role'];
        if (existingRole != null && existingRole != 'rider') {
          throw Exception(
            'uid "$uid" already belongs to a different role '
            '("$existingRole") — refusing to overwrite it with rider '
            'data. Create the rider under a separate account/uid.',
          );
        }
      }

      await userRef.set({
        'name': name,
        'phone': phone,
        'email': email ?? '',
        'branchId': branchId ?? '',
        'role': 'rider',
        'roleID': 'R003',
        'isAvailable': false,
        'totalOrders': 0,
        'delivered': 0,
        'pending': 0,
        'statusUpdatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("saveRiderData Error: $e");
      rethrow;
    }
  }

  Future<void> ensureRiderFields(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        Map<String, dynamic> updates = {};
        if (!data.containsKey('isAvailable')) updates['isAvailable'] = false;
        if (!data.containsKey('totalOrders')) updates['totalOrders'] = 0;
        if (!data.containsKey('delivered')) updates['delivered'] = 0;
        if (!data.containsKey('pending')) updates['pending'] = 0;

        if (updates.isNotEmpty) {
          await _firestore.collection('users').doc(uid).update(updates);
          debugPrint("✅ Missing fields added for rider: $uid");
        }
      }
    } catch (e) {
      debugPrint("ensureRiderFields Error: $e");
    }
  }

  Stream<DocumentSnapshot> getRiderStream(String riderId) {
    return _firestore.collection('users').doc(riderId).snapshots();
  }

  Future<void> updateRiderStatus(String riderId, bool newValue) async {
    try {
      await _firestore.collection('users').doc(riderId).update({
        'isAvailable': newValue,
        'statusUpdatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("updateRiderStatus Error: $e");
      rethrow;
    }
  }

  // ── LIVE LOCATION TRACKING ──────────────────────────────────

  Future<void> updateOrderLocation(
    String orderId,
    double lat,
    double lng,
  ) async {
    try {
      await _firestore.collection('orders').doc(orderId).update({
        'riderLat': lat,
        'riderLng': lng,
        'locationUpdatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("updateOrderLocation Error: $e");
    }
  }

  // ── PROFILE MANAGEMENT ──────────────────────────────────────

  Future<void> updateRiderProfileField(
    String riderId,
    String fieldKey,
    String value,
  ) async {
    try {
      await _firestore.collection('users').doc(riderId).set({
        fieldKey: value,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("updateRiderProfileField Error: $e");
      rethrow;
    }
  }

  /// 🟢 DIRECT UPDATE EMAIL IN BOTH AUTH & FIRESTORE
  Future<void> updateRiderEmail({
    required String riderId,
    required String newEmail,
    required String currentPassword,
  }) async {
    try {
      User? user = _auth.currentUser;
      if (user != null && user.email != null) {
        // 1. Re-authenticate User with Current Password
        AuthCredential credential = EmailAuthProvider.credential(
          email: user.email!,
          password: currentPassword,
        );
        UserCredential reauthResult = await user.reauthenticateWithCredential(
          credential,
        );

        // 2. Direct Auth Email Update (Bina Verification Email Link ke)
        await reauthResult.user?.updateEmail(newEmail);

        // 3. User State Sync / Reload
        await _auth.currentUser?.reload();

        // 4. Firestore Document Update
        await _firestore.collection('users').doc(riderId).update({
          'email': newEmail,
        });
      } else {
        throw Exception('No logged in user found.');
      }
    } on FirebaseAuthException catch (e) {
      debugPrint("updateRiderEmail Auth Error: ${e.code}");
      if (e.code == 'wrong-password') {
        throw Exception('Aap ka enter kiya hua password ghalat hai.');
      } else if (e.code == 'email-already-in-use') {
        throw Exception(
          'Yeh email kisi aur account ke sath already registered hai.',
        );
      } else if (e.code == 'invalid-email') {
        throw Exception('Email format sahi nahi hai.');
      } else if (e.code == 'requires-recent-login') {
        throw Exception('Security issue: Dobara logout karke login karein.');
      } else {
        throw Exception(e.message ?? 'Auth Error');
      }
    } catch (e) {
      debugPrint("updateRiderEmail Error: $e");
      rethrow;
    }
  }

  Future<void> uploadRiderPhoto(String riderId, File imageFile) async {
    try {
      final url = Uri.parse(
        'https://api.cloudinary.com/v1_1/$_cloudinaryCloudName/image/upload',
      );

      final request = http.MultipartRequest('POST', url)
        ..fields['upload_preset'] = _cloudinaryUploadPreset
        ..files.add(await http.MultipartFile.fromPath('file', imageFile.path));

      final response = await request.send();

      if (response.statusCode == 200) {
        final responseData = await response.stream.bytesToString();
        final jsonMap = jsonDecode(responseData);
        final String photoUrl = jsonMap['secure_url'];

        await _firestore.collection('users').doc(riderId).update({
          'photoUrl': photoUrl,
        });
      } else {
        throw Exception(
          'Cloudinary upload failed with status ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint("uploadRiderPhoto Error: $e");
      rethrow;
    }
  }

  Future<void> updateRiderPassword(String newPassword) async {
    try {
      User? user = _auth.currentUser;
      if (user != null) {
        await user.updatePassword(newPassword);
      } else {
        throw Exception('No logged in user found.');
      }
    } on FirebaseAuthException catch (e) {
      debugPrint("updateRiderPassword Auth Error: ${e.message}");
      if (e.code == 'requires-recent-login') {
        throw Exception(
          'Please re-authenticate before updating your password.',
        );
      }
      rethrow;
    } catch (e) {
      debugPrint("updateRiderPassword Error: $e");
      rethrow;
    }
  }

  // ── LIVE STREAMS & UPDATES (ORDERS SECTIONS) ──────────────────

  Stream<QuerySnapshot> getPendingOrdersStream(String riderId) {
    return _firestore
        .collection('orders')
        .where('order_status', isEqualTo: 'Assigned')
        .where('riderId', isEqualTo: riderId)
        .snapshots();
  }

  Stream<QuerySnapshot> getAcceptedOrdersStream(String riderId) {
    return _firestore
        .collection('orders')
        .where('order_status', isEqualTo: 'Accepted')
        .where('riderId', isEqualTo: riderId)
        .snapshots();
  }

  Future<void> acceptOrderInFirestore(String orderId, String riderId) async {
    try {
      await _firestore.collection('orders').doc(orderId).update({
        'order_status': 'Accepted',
        'riderId': riderId,
        'acceptedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("acceptOrderInFirestore Error: $e");
      rethrow;
    }
  }
}
