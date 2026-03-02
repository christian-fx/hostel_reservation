import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Service to generate, store, and verify 6-digit OTPs for admin login.
class OtpService {
  static final _firestore = FirebaseFirestore.instance;
  static const _otpCollection = 'admin_otps';
  static const _otpValidityMinutes = 5;

  /// Generate a random 6-digit OTP.
  static String generateOtp() {
    final random = Random.secure();
    final otp = 100000 + random.nextInt(900000); // 100000–999999
    return otp.toString();
  }

  /// Store the OTP in Firestore with an expiry timestamp.
  static Future<void> storeOtp(String adminUid, String otp) async {
    await _firestore.collection(_otpCollection).doc(adminUid).set({
      'otp': otp,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(
        DateTime.now().add(const Duration(minutes: _otpValidityMinutes)),
      ),
    });
  }

  /// Verify the OTP for the given admin UID.
  /// Returns `true` if valid and not expired, `false` otherwise.
  /// Deletes the OTP document after successful verification.
  static Future<bool> verifyOtp(String adminUid, String inputOtp) async {
    final doc = await _firestore.collection(_otpCollection).doc(adminUid).get();

    if (!doc.exists) return false;

    final data = doc.data()!;
    final storedOtp = data['otp'] as String;
    final expiresAt = data['expiresAt'] as Timestamp;

    // Check if expired
    if (DateTime.now().isAfter(expiresAt.toDate())) {
      // Clean up expired OTP
      await _firestore.collection(_otpCollection).doc(adminUid).delete();
      return false;
    }

    if (storedOtp != inputOtp) return false;

    // OTP matches — delete it so it can't be reused
    await _firestore.collection(_otpCollection).doc(adminUid).delete();
    return true;
  }
}
