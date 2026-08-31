import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotificationScreen extends StatelessWidget {
  const NotificationScreen({super.key});

  static const primaryColor = Color(0xFFE65100);

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFFEF9E7), // HomeScreen ka matching background
      appBar: AppBar(
        title: const Text('Notifications', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: currentUser == null
          ? const Center(child: Text('Please log in to see notifications.'))
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('notifications')
                  .where('userId', isEqualTo: currentUser.uid)
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: primaryColor));
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text('No notifications yet!', style: TextStyle(color: Colors.grey, fontSize: 16)),
                  );
                }

                final docs = snapshot.data!.docs;

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    // ✅ FIXED DATA CASTING
                    final data = doc.data() as Map<String, dynamic>? ?? {};
                    
                    final title = data['title'] ?? 'Notification';
                    final body = data['body'] ?? '';
                    final isRead = data['isRead'] ?? false;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      color: isRead ? Colors.grey.shade100 : Colors.white,
                      elevation: isRead ? 1 : 3,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isRead ? Colors.grey.shade300 : primaryColor.withOpacity(0.15),
                          child: Icon(
                            Icons.notifications_rounded,
                            color: isRead ? Colors.grey : primaryColor,
                          ),
                        ),
                        title: Text(
                          title,
                          style: TextStyle(
                            fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                            color: isRead ? Colors.black87 : Colors.black,
                          ),
                        ),
                        subtitle: Text(body, style: TextStyle(color: Colors.grey[600])),
                        onTap: () {
                          if (!isRead) {
                            FirebaseFirestore.instance
                                .collection('notifications')
                                .doc(doc.id)
                                .update({'isRead': true});
                          }
                        },
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}