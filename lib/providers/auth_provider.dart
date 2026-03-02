import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Stream provider that listens to auth state changes
final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

// Tracks whether the admin has been authenticated via OTP.
// In-memory only — resets when the app is restarted (intentional).
class AdminAuthNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setAuthenticated() => state = true;
  void clearAuthenticated() => state = false;
}

final adminAuthProvider = NotifierProvider<AdminAuthNotifier, bool>(
  AdminAuthNotifier.new,
);

/// Fetches the current user's role from Firestore.
/// Returns 'student' by default if the role field doesn't exist.
final userRoleProvider = FutureProvider<String?>((ref) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return null;

  final doc = await FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .get();

  if (!doc.exists) return null;

  final data = doc.data()!;
  return data.containsKey('role') ? data['role'] as String : 'student';
});
