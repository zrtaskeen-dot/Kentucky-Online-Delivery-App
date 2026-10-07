import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

// Capitalizes the first letter of every word as the user types (e.g.
// "ali khan" -> "Ali Khan"), and lower-cases the rest of that word.
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

class RiderProfileScreen extends StatefulWidget {
  final String riderId;
  const RiderProfileScreen({super.key, required this.riderId});

  // 👈 Matches Home screen's exact brand palette (maroon + white + card tint)
  static const Color primary = Color(0xFFA70000); // Maroon (same as Home)
  static const Color cardBgColor = Color(
    0xFFFFFDFA,
  ); // Card Color (same as Home)
  static const Color bgColor = Colors.white; // Theme Background (same as Home)

  @override
  State<RiderProfileScreen> createState() => _RiderProfileScreenState();
}

class _RiderProfileScreenState extends State<RiderProfileScreen> {
  static const bgColor = RiderProfileScreen.bgColor;
  static const cardColor = RiderProfileScreen.cardBgColor;
  static const primary = RiderProfileScreen.primary;

  // Phone number mein 11 digits se zyada nahi ho sakte.
  static const int _maxPhoneDigits = 11;

  final String _cloudName = "dqjqkwwwh";
  final String _uploadPreset = "rider_profiles";

  final ImagePicker _picker = ImagePicker();
  bool _isUploadingImage = false;

  // -- LOGOUT METHOD --
  Future<void> _logout() async {
    try {
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Logged out successfully',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: primary,
        ),
      );

      // Root navigator + pushNamedAndRemoveUntil('/', ...) taake bottom-nav
      // ke nested Navigator mein na phanse aur har screen clear ho jaye.
      Navigator.of(
        context,
        rootNavigator: true,
      ).pushNamedAndRemoveUntil('/', (route) => false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Logout failed: $e'),
            backgroundColor: Colors.black87,
          ),
        );
      }
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
              backgroundColor: primary,
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

  // ── Tap-to-edit dialog (customer ProfileScreen wala same dialog) ──
  void _editField(String fieldKey, String fieldLabel, String currentValue) {
    final isPhone = fieldKey == 'phone';
    final isName = fieldKey == 'name';

    var initial = currentValue == 'Not set' ? '' : currentValue;
    if (isPhone) {
      initial = initial.replaceAll(RegExp(r'\D'), '');
      if (initial.length > _maxPhoneDigits) {
        initial = initial.substring(initial.length - _maxPhoneDigits);
      }
    }
    final controller = TextEditingController(text: initial);

    final iconMap = {
      'name': Icons.person_outline_rounded,
      'phone': Icons.phone_outlined,
    };

    // StatefulBuilder ke BAHAR, warna har rebuild par null ho jata hai.
    String? fieldError;

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
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 28),
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: primary.withValues(alpha: 0.12),
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
                          color: cardColor,
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
                        keyboardType: isPhone
                            ? TextInputType.phone
                            : TextInputType.text,
                        textCapitalization: isName
                            ? TextCapitalization.words
                            : TextCapitalization.none,
                        maxLength: isPhone ? _maxPhoneDigits : null,
                        inputFormatters: isPhone
                            ? [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(
                                  _maxPhoneDigits,
                                ),
                              ]
                            : (isName ? [CapitalizeWordsFormatter()] : null),
                        onChanged: (_) {
                          if (fieldError != null) {
                            setDialogState(() => fieldError = null);
                          }
                        },
                        decoration: InputDecoration(
                          prefixIcon: Icon(
                            iconMap[fieldKey] ?? Icons.edit_outlined,
                            color: Colors.black45,
                            size: 20,
                          ),
                          hintText: 'Enter $fieldLabel',
                          counterText: isPhone ? '' : null,
                          errorText: fieldError,
                          filled: true,
                          fillColor: cardColor,
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
                                side: const BorderSide(
                                  color: Color(0xFFDDDDDD),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
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
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                elevation: 0,
                              ),
                              onPressed: () async {
                                final newVal = controller.text.trim();

                                if (newVal.isEmpty) {
                                  setDialogState(
                                    () => fieldError =
                                        '$fieldLabel cannot be empty',
                                  );
                                  return;
                                }

                                Navigator.pop(ctx);

                                try {
                                  await FirebaseFirestore.instance
                                      .collection('users')
                                      .doc(widget.riderId)
                                      .set({
                                        fieldKey: newVal,
                                      }, SetOptions(merge: true));

                                  // Auth ka displayName bhi sync rakho.
                                  if (isName) {
                                    await FirebaseAuth.instance.currentUser
                                        ?.updateDisplayName(newVal);
                                  }

                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        "$fieldLabel updated successfully",
                                      ),
                                      backgroundColor: primary,
                                    ),
                                  );
                                } catch (e) {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text("Update failed: $e"),
                                      backgroundColor: Colors.black87,
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
      },
    );
  }

  // ── Rider ki rectangular fields ──
  static const TextStyle _fieldTextStyle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: Colors.black87,
  );

  InputDecoration _boxDecoration(
    String label,
    IconData icon, {
    bool locked = false,
  }) {
    OutlineInputBorder border(Color color, [double width = 1.0]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: color, width: width),
        );

    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.black54, fontSize: 13),
      prefixIcon: Icon(icon, size: 20, color: primary),
      filled: true,
      fillColor: cardColor,
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      border: border(Colors.black38),
      enabledBorder: border(Colors.black38),
      disabledBorder: border(Colors.black38),
      focusedBorder: border(primary, 1.6),
    );
  }

  // fieldKey diya ho to tap par edit dialog khulta hai, warna field locked.
  Widget _profileFieldBox({
    required IconData icon,
    required String label,
    required String value,
    String? fieldKey,
  }) {
    final locked = fieldKey == null;
    final field = TextFormField(
      // Value badalne par naya text foran dikhane ke liye key.
      key: ValueKey('$label:$value'),
      initialValue: value,
      readOnly: true,
      enabled: !locked,
      style: _fieldTextStyle,
      decoration: _boxDecoration(label, icon, locked: locked).copyWith(
        suffixIcon: locked
            ? const Icon(
                Icons.lock_outline_rounded,
                size: 16,
                color: Colors.black26,
              )
            : const Icon(Icons.edit_outlined, size: 18, color: Colors.black38),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: locked
          ? field
          : GestureDetector(
              onTap: () => _editField(fieldKey, label, value),
              child: AbsorbPointer(child: field),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: bgColor,
        elevation: 0,
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
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(widget.riderId)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(
              child: CircularProgressIndicator(color: primary),
            );
          }

          final userData = snapshot.data!.data() as Map<String, dynamic>;
          final String imageUrl = (userData['imageUrl'] ?? '').toString();

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 16),

                // Interactive Profile Picture Avatar (customer jaisa)
                GestureDetector(
                  onTap: _isUploadingImage ? null : _pickProfileImage,
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
                          backgroundImage: imageUrl.isNotEmpty
                              ? NetworkImage(imageUrl)
                              : null,
                          child: _isUploadingImage
                              ? const CircularProgressIndicator(color: primary)
                              : imageUrl.isEmpty
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

                // -- PROFILE DATA (rider ki fields) --
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
                      _profileFieldBox(
                        icon: Icons.person_outline_rounded,
                        label: 'Full Name',
                        value: (userData['name'] ?? 'Not set').toString(),
                        fieldKey: 'name',
                      ),
                      _profileFieldBox(
                        icon: Icons.phone_outlined,
                        label: 'Phone Number',
                        value: (userData['phone'] ?? 'Not set').toString(),
                        fieldKey: 'phone',
                      ),
                      _profileFieldBox(
                        icon: Icons.email_outlined,
                        label: 'Email Address',
                        value: (userData['email'] ?? 'Not set').toString(),
                      ),
                      _profileFieldBox(
                        icon: Icons.badge_outlined,
                        label: 'CNIC Number',
                        value: (userData['cnic'] ?? 'Not set').toString(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // -- LOGOUT BUTTON (customer jaisa: 220x50, radius 30) --
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    fixedSize: const Size(220, 50),
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
                  onPressed: _logout,
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