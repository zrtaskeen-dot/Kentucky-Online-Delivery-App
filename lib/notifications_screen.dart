import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
// ⚠️ Adjust this path to wherever notification_service.dart actually lives
// in your project (e.g. '../services/notification_service.dart').
import 'notification_service.dart';

class NotificationScreen extends StatelessWidget {
  const NotificationScreen({super.key});

  static const primaryColor = Color(0xFFA70000); // App's standard maroon theme

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    // When this account was created — used to hide broadcast notifications
    // (new menu items/deals) that went out before this customer even
    // registered. Their personal, order-specific notifications are never
    // affected by this, since those can't exist before the account does.
    final accountCreatedAt = currentUser?.metadata.creationTime;

    return Scaffold(
      backgroundColor: Colors.white, // Matches Order Detail/History background
      appBar: AppBar(
        title: const Text(
          'Notifications',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: currentUser == null
            ? null
            : [
                IconButton(
                  icon: const Icon(Icons.delete_sweep_outlined),
                  tooltip: 'Delete all',
                  onPressed: () => _confirmDeleteAll(context, currentUser.uid),
                ),
              ],
      ),
      body: currentUser == null
          ? const Center(child: Text('Please log in to see notifications.'))
          : StreamBuilder<QuerySnapshot>(
              // 'ALL' catches store-wide notifications (new menu item/deal)
              // sent via NotificationService.broadcastToAllCustomers, while
              // currentUser.uid catches this customer's own order updates.
              stream: FirebaseFirestore.instance
                  .collection('notifications')
                  .where('userId', whereIn: [currentUser.uid, 'ALL'])
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: primaryColor),
                  );
                }

                // Show the real reason instead of silently saying "No
                // notifications yet!" — a missing composite index (needed
                // because this query combines whereIn with orderBy) shows
                // up as an error here, not as an empty list.
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'Could not load notifications:\n${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red, fontSize: 13),
                      ),
                    ),
                  );
                }

                // Firestore query already filtered by userId — now we also
                // drop any doc whose `hiddenFor` array contains this
                // customer's uid, i.e. notifications they've "deleted"
                // from their own list (the doc itself is untouched in the
                // database, and still shows to everyone else it's meant for).
                final allDocs = snapshot.data?.docs ?? [];
                final docs = allDocs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>? ?? {};
                  final hiddenFor = List<String>.from(
                    data['hiddenFor'] ?? const [],
                  );
                  if (hiddenFor.contains(currentUser.uid)) return false;

                  // New users shouldn't see store-wide broadcasts (new
                  // menu items / deals) that were sent before they even
                  // created their account — only ones sent from that
                  // point onward. If we don't know the account creation
                  // time for some reason, fail open (show it) rather than
                  // hiding a legitimate notification.
                  final notifUserId = data['userId'];
                  if (notifUserId == 'ALL' && accountCreatedAt != null) {
                    final ts = data['timestamp'];
                    if (ts is Timestamp &&
                        ts.toDate().isBefore(accountCreatedAt)) {
                      return false;
                    }
                  }

                  return true;
                }).toList();

                if (docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'No notifications yet!',
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  );
                }

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
                    final notifUserId = data['userId'];
                    final isBroadcast = notifUserId == 'ALL';
                    final timestampLabel = _formatPakistaniTimestamp(
                      data['timestamp'],
                    );

                    return Dismissible(
                      key: ValueKey(doc.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),

                      confirmDismiss: (_) => _showThemedConfirm(
                        context,
                        title: 'Delete notification?',
                        message: 'Do you want to delete this notification?',
                        confirmLabel: 'Delete',
                      ),
                      onDismissed: (_) {
                        NotificationService.hideNotificationForUser(
                          notificationId: doc.id,
                          userId: currentUser.uid,
                        );
                      },
                      child: Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        color: const Color(0xFFFFFDFA),
                        elevation: isRead ? 1 : 3,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isRead
                                ? Colors.grey.shade300
                                : primaryColor.withValues(alpha: 0.15),
                            child: Icon(
                              Icons.notifications_rounded,
                              color: isRead ? Colors.grey : primaryColor,
                            ),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  style: TextStyle(
                                    fontWeight: isRead
                                        ? FontWeight.normal
                                        : FontWeight.bold,
                                    color: isRead
                                        ? Colors.black87
                                        : Colors.black,
                                  ),
                                ),
                              ),
                              if (!isRead)
                                Container(
                                  margin: const EdgeInsets.only(left: 6),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: primaryColor,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'NEW',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                body,
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                              if (timestampLabel.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  timestampLabel,
                                  style: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          trailing: IconButton(
                            icon: Icon(
                              Icons.delete_outline_rounded,
                              color: primaryColor.withValues(alpha: 0.7),
                            ),
                            tooltip: 'Delete',
                            onPressed: () => _confirmDeleteOne(
                              context,
                              doc.id,
                              currentUser.uid,
                            ),
                          ),
                          onTap: () {
                            if (!isRead) {
                              FirebaseFirestore.instance
                                  .collection('notifications')
                                  .doc(doc.id)
                                  .update({'isRead': true});
                            }
                          },
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  // ── DELETE (HIDE-ONLY) HELPERS ──
  // "Delete" here always means: hide from this customer's own list.
  // The Firestore document itself is never removed.

  static const _cardWhite = Color(0xFFFFFDFA);

  // Pakistani-style date/time: DD/MM/YYYY (day before month, not the
  // US MM/DD/YYYY order) with a 12-hour clock + AM/PM, e.g.
  // "15/09/2026, 4:45 PM". Firestore's serverTimestamp() is stored in
  // UTC internally — .toDate().toLocal() converts it to the device's
  // local time before formatting.
  String _formatPakistaniTimestamp(dynamic raw) {
    if (raw is! Timestamp) return '';
    final dt = raw.toDate().toLocal();

    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final year = dt.year.toString();

    int hour12 = dt.hour % 12;
    if (hour12 == 0) hour12 = 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';

    return '$day/$month/$year, $hour12:$minute $period';
  }

  // Shared app-themed confirmation dialog. Returns true only if the
  // person tapped the destructive action.
  Future<bool> _showThemedConfirm(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _cardWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: Colors.black87,
          ),
        ),
        content: Text(
          message,
          style: TextStyle(color: Colors.grey[700], fontSize: 13),
        ),
        actionsPadding: const EdgeInsets.only(right: 12, bottom: 8),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            style: TextButton.styleFrom(foregroundColor: Colors.grey[600]),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: primaryColor),
            child: Text(
              confirmLabel,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _confirmDeleteOne(
    BuildContext context,
    String notificationId,
    String currentUserId,
  ) async {
    final confirmed = await _showThemedConfirm(
      context,
      title: 'Delete notification?',
      message: 'Do you want to delete this notification?',
      confirmLabel: 'Delete',
    );
    if (confirmed) {
      NotificationService.hideNotificationForUser(
        notificationId: notificationId,
        userId: currentUserId,
      );
    }
  }

  Future<void> _confirmDeleteAll(BuildContext context, String uid) async {
    final confirmed = await _showThemedConfirm(
      context,
      title: 'Delete all notifications?',
      message: 'Do you want to delete all notifications?',
      confirmLabel: 'Delete all',
    );
    if (confirmed) {
      NotificationService.hideAllNotificationsForUser(uid);
    }
  }
}
