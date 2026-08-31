import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class RiderProfileScreen extends StatefulWidget {
  final String riderId;
  const RiderProfileScreen({super.key, required this.riderId});

  static const Color primary = Color(0xFFA30000); // Maroon
  static const Color cardBgColor = Color(0xFFFFFFF0); // Card Color
  static const Color bgColor = Color(0xFFFFFDF0); // Theme Background

  @override
  State<RiderProfileScreen> createState() => _RiderProfileScreenState();
}

class _RiderProfileScreenState extends State<RiderProfileScreen> {
  // -------------------------------------------------------------
  // ⚙️ CLOUDINARY CONFIGURATION
  // -------------------------------------------------------------
  final String _cloudName = "dqjqkwwwh";
  final String _uploadPreset = "rider_profiles";

  final ImagePicker _picker = ImagePicker();
  bool _isUploadingImage = false;
  bool _isLoggingOut = false;

  // -- LOGOUT METHOD --
  Future<void> _logout() async {
    setState(() => _isLoggingOut = true);
    try {
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;

      Navigator.of(context).popUntil((route) => route.isFirst);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Logged out successfully',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: RiderProfileScreen.primary,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Logout failed: $e'),
            backgroundColor: Colors.black87,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoggingOut = false);
    }
  }

  // -- CLOUDINARY IMAGE PICKER + UPLOAD --
  Future<void> _pickProfileImage() async {
    final XFile? picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (picked == null) return;

    setState(() => _isUploadingImage = true);

    try {
      final uri = Uri.parse(
        'https://api.cloudinary.com/v1_1/$_cloudName/image/upload',
      );

      var request = http.MultipartRequest('POST', uri)
        ..fields['upload_preset'] = _uploadPreset
        ..files.add(await http.MultipartFile.fromPath('file', picked.path));

      var response = await request.send();

      if (response.statusCode == 200) {
        final responseData = await response.stream.bytesToString();
        final jsonMap = jsonDecode(responseData);
        final String downloadUrl = jsonMap['secure_url'];

        await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.riderId)
            .set({'imageUrl': downloadUrl}, SetOptions(merge: true));

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Profile photo updated',
                style: TextStyle(color: Colors.white),
              ),
              backgroundColor: RiderProfileScreen.primary,
            ),
          );
        }
      } else {
        throw Exception('Cloudinary upload failed');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload photo: $e'),
            backgroundColor: Colors.black87,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  // -- POPUP DIALOG TO EDIT PROFILE DATA --
  void _showEditProfileDialog(Map<String, dynamic> currentData) {
    final nameController = TextEditingController(
      text: currentData['name'] ?? '',
    );
    final phoneController = TextEditingController(
      text: currentData['phone'] ?? '',
    );
    final emailController = TextEditingController(
      text: currentData['email'] ?? '',
    );
    final cnicController = TextEditingController(
      text: currentData['cnic'] ?? '',
    );

    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: RiderProfileScreen.cardBgColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text(
                'Edit Profile',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Editable Name Field
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        prefixIcon: Icon(
                          Icons.person,
                          color: RiderProfileScreen.primary,
                        ),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Editable Phone Field
                    TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone Number',
                        prefixIcon: Icon(
                          Icons.phone,
                          color: RiderProfileScreen.primary,
                        ),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Fixed / Disabled Email Field
                    TextField(
                      controller: emailController,
                      enabled: false,
                      decoration: InputDecoration(
                        labelText: 'Email Address (Fixed)',
                        prefixIcon: const Icon(
                          Icons.email,
                          color: Colors.grey,
                        ),
                        border: const OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.grey.shade200,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Fixed / Disabled CNIC Field
                    TextField(
                      controller: cnicController,
                      enabled: false,
                      decoration: InputDecoration(
                        labelText: 'CNIC (Fixed)',
                        prefixIcon: const Icon(
                          Icons.badge,
                          color: Colors.grey,
                        ),
                        border: const OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.grey.shade200,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(context),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: RiderProfileScreen.primary,
                  ),
                  onPressed: isSaving
                      ? null
                      : () async {
                          setDialogState(() => isSaving = true);

                          try {
                            await FirebaseFirestore.instance
                                .collection('users')
                                .doc(widget.riderId)
                                .update({
                              'name': nameController.text.trim(),
                              'phone': phoneController.text.trim(),
                            });

                            if (mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Profile updated successfully',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  backgroundColor: RiderProfileScreen.primary,
                                ),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Update failed: $e'),
                                  backgroundColor: Colors.black87,
                                ),
                              );
                            }
                          } finally {
                            setDialogState(() => isSaving = false);
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Save',
                          style: TextStyle(color: Colors.white),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RiderProfileScreen.bgColor,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text(
          'My Profile',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: RiderProfileScreen.bgColor,
        centerTitle: true,
        elevation: 0,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(widget.riderId)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(
              child: CircularProgressIndicator(
                color: RiderProfileScreen.primary,
              ),
            );
          }

          final userData = snapshot.data!.data() as Map<String, dynamic>;
          final imageUrl = userData['imageUrl'] ?? '';

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                const SizedBox(height: 10),

                // -- CLICKABLE PROFILE IMAGE --
                GestureDetector(
                  onTap: _isUploadingImage ? null : _pickProfileImage,
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 52,
                        backgroundColor: RiderProfileScreen.primary,
                        child: CircleAvatar(
                          radius: 49,
                          backgroundColor: Colors.grey.shade300,
                          backgroundImage: imageUrl.isNotEmpty
                              ? NetworkImage(imageUrl)
                              : null,
                          child: imageUrl.isEmpty
                              ? const Icon(
                                  Icons.person,
                                  size: 60,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: RiderProfileScreen.primary,
                            shape: BoxShape.circle,
                          ),
                          child: _isUploadingImage
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.camera_alt,
                                  color: Colors.white,
                                  size: 18,
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // -- PROFILE DATA DISPLAY CARD --
                Card(
                  color: RiderProfileScreen.cardBgColor,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(
                            Icons.person,
                            color: RiderProfileScreen.primary,
                          ),
                          title: const Text(
                            'Full Name',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          subtitle: Text(
                            userData['name'] ?? 'Not set',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                        ),
                        const Divider(),
                        ListTile(
                          leading: const Icon(
                            Icons.phone,
                            color: RiderProfileScreen.primary,
                          ),
                          title: const Text(
                            'Phone Number',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          subtitle: Text(
                            userData['phone'] ?? 'Not set',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                        ),
                        const Divider(),
                        ListTile(
                          leading: const Icon(
                            Icons.email,
                            color: RiderProfileScreen.primary,
                          ),
                          title: const Text(
                            'Email Address',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          subtitle: Text(
                            userData['email'] ?? 'Not set',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                        ),
                        const Divider(),
                        ListTile(
                          leading: const Icon(
                            Icons.badge,
                            color: RiderProfileScreen.primary,
                          ),
                          title: const Text(
                            'CNIC Number',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          subtitle: Text(
                            userData['cnic'] ?? 'Not set',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // -- EDIT PROFILE BUTTON --
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(
                        color: RiderProfileScreen.primary,
                        width: 2,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(
                      Icons.edit,
                      color: RiderProfileScreen.primary,
                    ),
                    label: const Text(
                      'Edit Profile Details',
                      style: TextStyle(
                        color: RiderProfileScreen.primary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () => _showEditProfileDialog(userData),
                  ),
                ),

                const SizedBox(height: 14),

                // -- LOGOUT BUTTON --
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: RiderProfileScreen.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 3,
                    ),
                    icon: _isLoggingOut
                        ? const SizedBox.shrink()
                        : const Icon(Icons.logout, color: Colors.white),
                    label: _isLoggingOut
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Logout',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                    onPressed: _isLoggingOut ? null : _logout,
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }
}