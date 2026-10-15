import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'rider/rider_auth_repository.dart'; 

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