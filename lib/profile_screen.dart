import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const bgColor = Color(0xFFFEF9E7);
  static const primary = Color(0xFFA62600); // Maroon Color
  static const cardColor = Color(0xFFFFFFF0);

  // Cloudinary credentials
  static const String _cloudinaryUrl =
      "https://api.cloudinary.com/v1_1/dqjqkwwwh/image/upload";
  static const String _profileUploadPreset = "payment_receipts";

  final user = FirebaseAuth.instance.currentUser;
  Map<String, dynamic> _userData = {};
  bool _isLoading = true;
  bool _isUploadingImage = false;
  File? _imageFile;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    try {
      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .get();

      final data = doc.exists ? (doc.data() ?? {}) : <String, dynamic>{};

      // ── FIXED: order data now only fills in as a FALLBACK ──────────
      // Pehle ye block phone_number/address ko HAMESHA overwrite kar
      // deta tha latest order ki value se, chahe user ne apne profile
      // mein khud value save ki ho. Isi wajah se Profile screen pe
      // edit karne ke baad bhi purani (order wali) value dobara dikh
      // jati thi jab screen reload hoti thi. Ab ye sirf tab use hota
      // hai jab user ki apni profile mein wo field khali ho.
      try {
        final uid = user!.uid;

        var orderSnap = await FirebaseFirestore.instance
            .collection('orders')
            .where('userId', isEqualTo: uid)
            .get();

        if (orderSnap.docs.isEmpty) {
          orderSnap = await FirebaseFirestore.instance
              .collection('orders')
              .where('customerId', isEqualTo: uid)
              .get();
        }

        if (orderSnap.docs.isNotEmpty) {
          final docs = orderSnap.docs;

          docs.sort((a, b) {
            final aTime = a.data()['order_date'] ?? a.data()['createdAt'];
            final bTime = b.data()['order_date'] ?? b.data()['createdAt'];
            if (aTime == null || bTime == null) return 0;
            return (bTime as Timestamp).compareTo(aTime as Timestamp);
          });

          final latestOrder = docs.first.data();
          final orderPhone =
              (latestOrder['phone_number'] ?? latestOrder['phone'] ?? '')
                  .toString();
          final orderAddress =
              (latestOrder['delivery_address'] ?? latestOrder['address'] ?? '')
                  .toString();

          final existingPhone = (data['phone_number'] ?? '').toString();
          final existingAddress = (data['address'] ?? '').toString();

          // Only fall back to order data if user hasn't set their own value.
          if (existingPhone.trim().isEmpty && orderPhone.trim().isNotEmpty) {
            data['phone_number'] = orderPhone;
          }
          if (existingAddress.trim().isEmpty &&
              orderAddress.trim().isNotEmpty) {
            data['address'] = orderAddress;
          }
        }
      } catch (e) {
        debugPrint("Order fetch error: $e");
      }
      // ─────────────────────────────────────────────────────────────

      setState(() {
        _userData = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  // Profile Picture Upload Logic
  Future<void> _pickAndUploadImage() async {
    final XFile? pickedFile = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );

    if (pickedFile == null) return;

    setState(() {
      _imageFile = File(pickedFile.path);
      _isUploadingImage = true;
    });

    try {
      final request = http.MultipartRequest('POST', Uri.parse(_cloudinaryUrl))
        ..fields['upload_preset'] = _profileUploadPreset
        ..files.add(
          await http.MultipartFile.fromPath('file', _imageFile!.path),
        );

      final streamedResponse = await request.send();
      final responseBody = await streamedResponse.stream.bytesToString();

      if (streamedResponse.statusCode == 200) {
        final data = jsonDecode(responseBody);
        final String photoUrl = data['secure_url'];

        // Update Firestore
        await FirebaseFirestore.instance.collection('users').doc(user!.uid).set(
          {'photoUrl': photoUrl},
          SetOptions(merge: true),
        );

        // Update Auth Profile
        await user?.updatePhotoURL(photoUrl);

        setState(() {
          _userData['photoUrl'] = photoUrl;
          _isUploadingImage = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Profile picture updated successfully"),
              backgroundColor: primary, // Maroon
            ),
          );
        }
      } else {
        throw Exception("Upload failed");
      }
    } catch (e) {
      setState(() => _isUploadingImage = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to upload photo: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _editField(String fieldKey, String fieldLabel, String currentValue) {
    final controller = TextEditingController(text: currentValue);
    final iconMap = {
      'name': Icons.person_outline_rounded,
      'phone_number': Icons.phone_outlined,
      'address': Icons.location_on_outlined,
    };

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black45,
      transitionDuration: const Duration(milliseconds: 300),
      transitionBuilder: (_, anim, __, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.15),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: FadeTransition(opacity: anim, child: child),
        );
      },
      pageBuilder: (ctx, _, __) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 28),
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: bgColor, // CHANGED: cream instead of white
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: primary.withOpacity(0.12),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: cardColor, // CHANGED: cream instead of grey
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      iconMap[fieldKey] ?? Icons.edit_outlined,
                      color: Colors.black54,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Edit $fieldLabel',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Update your $fieldLabel below',
                    style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                  ),
                  const SizedBox(height: 22),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: fieldKey == 'phone_number'
                        ? TextInputType.phone
                        : TextInputType.text,
                    decoration: InputDecoration(
                      prefixIcon: Icon(
                        iconMap[fieldKey] ?? Icons.edit_outlined,
                        color: Colors.black45,
                        size: 20,
                      ),
                      hintText: 'Enter $fieldLabel',
                      filled: true,
                      fillColor:
                          cardColor, // CHANGED: cream instead of Color(0xFFFAF7F0)
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: primary,
                          width: 1.5,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 16,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFFDDDDDD)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              color: Colors.grey,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primary,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                          onPressed: () async {
                            Navigator.pop(ctx);
                            final newVal = controller.text.trim();

                            await FirebaseFirestore.instance
                                .collection('users')
                                .doc(user!.uid)
                                .set({
                                  fieldKey: newVal,
                                }, SetOptions(merge: true));

                            // ── ADDED: keep FirebaseAuth's displayName in
                            // sync when the "name" field is edited, so any
                            // screen reading FirebaseAuth.currentUser
                            // directly (instead of Firestore) also updates.
                            if (fieldKey == 'name') {
                              await user?.updateDisplayName(newVal);
                              await user?.reload();
                            }

                            setState(() => _userData[fieldKey] = newVal);

                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    "$fieldLabel updated successfully",
                                  ),
                                  backgroundColor: primary, // Maroon
                                ),
                              );
                            }
                          },
                          child: const Text(
                            'Save',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _openTermsAndConditions() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const _TermsAndConditionsScreen()),
    );
  }

  Widget _buildFieldBox({
    required IconData icon,
    required String label,
    required String value,
    required String fieldKey,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GestureDetector(
        onTap: () => _editField(fieldKey, label, value),
        child: AbsorbPointer(
          child: TextFormField(
            initialValue: value,
            readOnly: true,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
            decoration: InputDecoration(
              labelText: label,
              labelStyle: const TextStyle(color: Colors.black54, fontSize: 13),
              hintText: value.isEmpty ? 'Tap to add' : null,
              prefixIcon: Icon(icon, size: 20, color: primary),
              suffixIcon: const Icon(
                Icons.edit_outlined,
                size: 18,
                color: Colors.black38,
              ),
              filled: true,
              fillColor: cardColor,
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
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmailBox({required String value}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        initialValue: value,
        readOnly: true,
        enabled: false,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
        decoration: InputDecoration(
          labelText: 'Email Address',
          labelStyle: const TextStyle(color: Colors.black54, fontSize: 13),
          prefixIcon: const Icon(
            Icons.email_outlined,
            size: 20,
            color: primary,
          ),
          suffixIcon: const Icon(
            Icons.lock_outline_rounded,
            size: 16,
            color: Colors.black26,
          ),
          filled: true,
          fillColor: cardColor,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 16,
            horizontal: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.black38),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.black38),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name =
        _userData['name'] ?? _userData['fullName'] ?? user?.displayName ?? '';
    final email = _userData['email'] ?? user?.email ?? '';
    final phone = _userData['phone_number'] ?? user?.phoneNumber ?? '';
    final address = _userData['address'] ?? '';
    final photoUrl = _userData['photoUrl'] ?? user?.photoURL;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: primary,
            size: 22,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'My Profile',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const SizedBox(height: 16),

                  // Interactive Profile Picture Avatar
                  GestureDetector(
                    onTap: _isUploadingImage ? null : _pickAndUploadImage,
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.fromBorderSide(
                              BorderSide(color: primary, width: 2.5),
                            ),
                          ),
                          child: CircleAvatar(
                            radius: 52,
                            backgroundColor: const Color(0xFFE0E0E0),
                            backgroundImage:
                                photoUrl != null && photoUrl.isNotEmpty
                                ? NetworkImage(photoUrl)
                                : null,
                            child: _isUploadingImage
                                ? const CircularProgressIndicator(
                                    color: primary,
                                  )
                                : (photoUrl == null || photoUrl.isEmpty)
                                ? const Icon(
                                    Icons.person_rounded,
                                    size: 56,
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: const BoxDecoration(
                            color: primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.camera_alt_rounded,
                            size: 15,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [
                        BoxShadow(
                          color: Color.fromRGBO(0, 0, 0, 0.05),
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        _buildFieldBox(
                          icon: Icons.person_outline_rounded,
                          label: 'Full Name',
                          value: name,
                          fieldKey: 'name',
                        ),
                        _buildEmailBox(value: email),
                        _buildFieldBox(
                          icon: Icons.phone_outlined,
                          label: 'Phone Number',
                          value: phone,
                          fieldKey: 'phone_number',
                        ),
                        _buildFieldBox(
                          icon: Icons.location_on_outlined,
                          label: 'Address',
                          value: address,
                          fieldKey: 'address',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primary,
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 0,
                    ),
                    icon: const Icon(
                      Icons.logout_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    label: const Text(
                      'Logout',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () async {
                      await FirebaseAuth.instance.signOut();
                      if (context.mounted) {
                        Navigator.pushNamedAndRemoveUntil(
                          context,
                          '/',
                          (route) => false,
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                  TextButton(
                    onPressed: _openTermsAndConditions,
                    child: const Text(
                      'Terms & Conditions',
                      style: TextStyle(
                        color: primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }
}

class _TermsAndConditionsScreen extends StatelessWidget {
  const _TermsAndConditionsScreen();

  static const primary = Color(0xFFA62600);
  static const bgColor = Color(0xFFFEF9E7);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: primary,
            size: 22,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Terms & Conditions',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: Text(
          'Welcome to our app. By using this app you agree to the '
          'following terms and conditions.\n\n'
          '1. Orders once placed cannot be modified after they are '
          'confirmed by the restaurant.\n\n'
          '2. Delivery times are estimates and may vary due to traffic, '
          'weather, or other conditions beyond our control.\n\n'
          '3. Payment must be completed through the supported methods '
          'shown at checkout.\n\n'
          '4. Personal information (name, phone, address) is used only '
          'to process and deliver your orders.\n\n'
          '5. We reserve the right to update these terms at any time; '
          'continued use of the app means you accept the updated terms.\n\n'
          ,
          style: TextStyle(fontSize: 14, height: 1.6, color: Colors.black87),
        ),
      ),
    );
  }
}