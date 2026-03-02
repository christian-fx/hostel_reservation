import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

/// Service to send OTP emails to admin users via SMTP.
///
/// ⚠️  IMPORTANT: Replace the placeholder credentials below with real values.
///     For Gmail, generate an App Password at:
///     https://myaccount.google.com/apppasswords
class EmailService {
  // ── SMTP Configuration ──────────────────────────────────────────────────
  // TODO: Replace with your actual SMTP credentials
  static const _smtpHost = 'smtp.gmail.com';
  static const _smtpPort = 587;
  static const _smtpUsername = 'madukajesse14@gmail.com';
  static const _smtpPassword = 'kpit bbsw vlht cxih';
  // ────────────────────────────────────────────────────────────────────────

  /// Send OTP email to [recipientEmail].
  static Future<bool> sendOtpEmail({
    required String recipientEmail,
    required String otp,
  }) async {
    final smtpServer = SmtpServer(
      _smtpHost,
      port: _smtpPort,
      username: _smtpUsername,
      password: _smtpPassword,
    );

    final message = Message()
      ..from = Address(_smtpUsername, 'Hostel Reservation Admin')
      ..recipients.add(recipientEmail)
      ..subject = 'Your Admin Login OTP'
      ..html =
          '''
        <div style="font-family: Arial, sans-serif; max-width: 480px; margin: auto; padding: 24px;">
          <h2 style="color: #0F172A;">Admin Login Verification</h2>
          <p>Your one-time password (OTP) for admin login is:</p>
          <div style="
            font-size: 32px;
            font-weight: bold;
            letter-spacing: 8px;
            color: #16a34a;
            background: #f0fdf4;
            border: 2px solid #bbf7d0;
            border-radius: 12px;
            padding: 16px;
            text-align: center;
            margin: 16px 0;
          ">$otp</div>
          <p style="color: #64748b; font-size: 14px;">
            This OTP is valid for <strong>5 minutes</strong>. Do not share it with anyone.
          </p>
          <hr style="border: none; border-top: 1px solid #e2e8f0; margin: 24px 0;">
          <p style="color: #94a3b8; font-size: 12px;">
            Hostel Reservation System — FUTO
          </p>
        </div>
      ''';

    try {
      await send(message, smtpServer);
      return true;
    } catch (e) {
      print('❌ Failed to send OTP email: $e');
      return false;
    }
  }
}
