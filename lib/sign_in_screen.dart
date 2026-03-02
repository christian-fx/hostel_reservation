// presentation/screens/sign_in_screen.dart
//
// Purpose: Authentication entry point.
// Responsibility: Allows existing students to log in using their credentials.
//   Admin: Firebase Auth login → role check → OTP sent to email → admin dashboard.
// Navigation: Login -> MainScreen | "Sign Up" -> RegistrationScreen

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'app_theme.dart';
import 'notifications/fcm_token_store.dart';
import 'providers/auth_provider.dart';
import 'services/otp_service.dart';
import 'services/email_service.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _otpFormKey = GlobalKey<FormState>();

  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _showOtpStep = false; // true when OTP step is visible (admin only)
  bool _isSendingOtp = false;

  final _regNumberController = TextEditingController();
  final _passwordController = TextEditingController();
  final _otpController = TextEditingController();

  // Stored after successful admin login, before OTP verification
  String? _adminUid;
  String? _adminEmail;

  late final AnimationController _slideController;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.25),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _regNumberController.dispose();
    _passwordController.dispose();
    _otpController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  Sign In logic
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;

    final input = _regNumberController.text.trim();
    final password = _passwordController.text;

    setState(() => _isLoading = true);

    try {
      // Detect if user entered an email or a reg number
      final bool isEmail = input.contains('@');

      // Look up the user in Firestore
      final querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where(isEmail ? 'email' : 'regNumber', isEqualTo: input)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        throw Exception(
          isEmail
              ? 'No account found with this email.'
              : 'No account found with this registration number.',
        );
      }

      final userDoc = querySnapshot.docs.first;
      final email = userDoc.get('email') as String;
      final role = userDoc.data().containsKey('role')
          ? userDoc.get('role') as String
          : 'student';

      // Authenticate with Firebase Auth
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Authentication failed.');

      await saveFcmTokenForUser(user.uid);
      print("✅ Logged in uid: ${user.uid}");

      // ── Role-based branching ──────────────────────────────────────────
      if (role == 'admin') {
        // Admin detected — send OTP and show OTP step
        _adminUid = user.uid;
        _adminEmail = email;

        // Sign OUT so the admin isn't fully authenticated yet
        // (they must verify OTP first)
        await FirebaseAuth.instance.signOut();

        await _sendOtp();

        setState(() {
          _showOtpStep = true;
        });
        _slideController.forward(from: 0);
      }
      // else: student — auth state listener in router handles redirect
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'user-not-found':
          message = 'No user found for this registration number.';
          break;
        case 'wrong-password':
          message = 'Incorrect password.';
          break;
        case 'invalid-email':
          message = 'Invalid email format.';
          break;
        case 'user-disabled':
          message = 'This account has been disabled.';
          break;
        default:
          message = 'Sign in failed: ${e.message}';
      }
      _showError(message);
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Send OTP to admin email ────────────────────────────────────────────
  Future<void> _sendOtp() async {
    if (_adminUid == null || _adminEmail == null) return;

    setState(() => _isSendingOtp = true);

    try {
      final otp = OtpService.generateOtp();
      await OtpService.storeOtp(_adminUid!, otp);

      final sent = await EmailService.sendOtpEmail(
        recipientEmail: _adminEmail!,
        otp: otp,
      );

      if (!sent) {
        _showError('Failed to send OTP email. Please try again.');
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('OTP sent to $_adminEmail'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      _showError('Error sending OTP: $e');
    } finally {
      if (mounted) setState(() => _isSendingOtp = false);
    }
  }

  // ── Verify the OTP ─────────────────────────────────────────────────────
  Future<void> _verifyOtp() async {
    if (!_otpFormKey.currentState!.validate()) return;
    if (_adminUid == null || _adminEmail == null) return;

    setState(() => _isLoading = true);

    try {
      final isValid = await OtpService.verifyOtp(
        _adminUid!,
        _otpController.text.trim(),
      );

      if (isValid) {
        // Re-sign in the admin now that OTP is verified
        // We need their password to re-authenticate
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _adminEmail!,
          password: _passwordController.text,
        );

        // Mark admin as authenticated in Riverpod so the router allows /admin/*
        ref.read(adminAuthProvider.notifier).setAuthenticated();
        context.go('/admin/hostels');
      } else {
        _showError('Invalid or expired OTP. Please try again.');
      }
    } catch (e) {
      _showError('Verification failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Go back to step 1 ─────────────────────────────────────────────────
  void _backToCredentials() {
    _slideController.reverse().then((_) {
      if (mounted) {
        setState(() {
          _showOtpStep = false;
          _otpController.clear();
          _adminUid = null;
          _adminEmail = null;
        });
      }
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  Build
  // ──────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 450),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // ── Logo ─────────────────────────────────────────────────
                  Container(
                    width: 96,
                    height: 96,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.asset(
                      'assets/images/futo_logo.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Hostel Reservation',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      _showOtpStep
                          ? 'Enter the OTP sent to your email'
                          : 'Sign in to manage your accommodation',
                      key: ValueKey(_showOtpStep),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Step 1: Credentials form ──────────────────────────────
                  AnimatedOpacity(
                    opacity: _showOtpStep ? 0.0 : 1.0,
                    duration: const Duration(milliseconds: 250),
                    child: IgnorePointer(
                      ignoring: _showOtpStep,
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _fieldLabel('Email or Reg Number', isDark),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _regNumberController,
                              decoration: const InputDecoration(
                                hintText:
                                    'e.g., 2018/123456 or email@futo.edu.ng',
                              ),
                              validator: (v) =>
                                  (v == null || v.isEmpty) ? 'Required' : null,
                            ),
                            const SizedBox(height: 16),
                            _fieldLabel('Password', isDark),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              decoration: InputDecoration(
                                hintText: 'Enter your password',
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility
                                        : Icons.visibility_off,
                                    color: Colors.grey.shade400,
                                  ),
                                  onPressed: () => setState(
                                    () => _obscurePassword = !_obscurePassword,
                                  ),
                                ),
                              ),
                              validator: (v) =>
                                  (v == null || v.isEmpty) ? 'Required' : null,
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () {},
                                child: const Text('Forgot Password?'),
                              ),
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton(
                              onPressed: _isLoading ? null : _signIn,
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Sign In'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // ── Step 2: Admin OTP verification ─────────────────────────
                  if (_showOtpStep)
                    SlideTransition(
                      position: _slideAnimation,
                      child: FadeTransition(
                        opacity: _slideController,
                        child: Form(
                          key: _otpFormKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Admin badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                  horizontal: 16,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryColor.withOpacity(
                                    0.08,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppTheme.primaryColor.withOpacity(
                                      0.3,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: const [
                                    Icon(
                                      Icons.admin_panel_settings_rounded,
                                      color: AppTheme.primaryColor,
                                      size: 20,
                                    ),
                                    SizedBox(width: 10),
                                    Text(
                                      'Admin Access Detected',
                                      style: TextStyle(
                                        color: AppTheme.primaryColor,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              // Email info
                              Text(
                                'OTP sent to: ${_adminEmail ?? ''}',
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.grey.shade400
                                      : Colors.grey.shade600,
                                  fontSize: 13,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 20),
                              _fieldLabel('Enter OTP', isDark),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _otpController,
                                keyboardType: TextInputType.number,
                                maxLength: 6,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 8,
                                ),
                                decoration: InputDecoration(
                                  hintText: '------',
                                  counterText: '',
                                  prefixIcon: const Icon(
                                    Icons.lock_outline_rounded,
                                    color: AppTheme.primaryColor,
                                  ),
                                ),
                                validator: (v) {
                                  if (v == null || v.isEmpty) return 'Required';
                                  if (v.length != 6) return 'Enter 6 digits';
                                  return null;
                                },
                              ),
                              const SizedBox(height: 24),
                              ElevatedButton(
                                onPressed: _isLoading ? null : _verifyOtp,
                                child: _isLoading
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('Verify & Access Dashboard'),
                              ),
                              const SizedBox(height: 12),
                              // Resend OTP button
                              TextButton(
                                onPressed: _isSendingOtp ? null : _sendOtp,
                                child: _isSendingOtp
                                    ? const SizedBox(
                                        height: 16,
                                        width: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text(
                                        'Resend OTP',
                                        style: TextStyle(
                                          color: AppTheme.primaryColor,
                                        ),
                                      ),
                              ),
                              const SizedBox(height: 4),
                              TextButton(
                                onPressed: _backToCredentials,
                                child: const Text(
                                  '← Back to Sign In',
                                  style: TextStyle(
                                    color: AppTheme.primaryColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // ── Footer: Sign Up link (hidden during OTP step) ─────────
                  if (!_showOtpStep) ...[
                    const SizedBox(height: 48),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Don't have an account? ",
                          style: TextStyle(
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade500,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => context.push('/register'),
                          child: const Text(
                            'Sign Up',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 32),
                  Container(
                    width: 100,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.grey.shade700
                          : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(String text, bool isDark) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w500,
        color: isDark ? Colors.grey.shade200 : const Color(0xFF0F172A),
      ),
    );
  }
}
