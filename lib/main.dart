import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';

import 'auth_service.dart';

void main() => runApp(const SpodaApp());

abstract final class AppColors {
  static const background = Color(0xFF000000); //0xFF090909 0xFF404040
  static const surface = Color(0xFF151515);
  static const border = Color(0xFF333333);
  static const muted = Color(0xFFAAAAAA);
  static const acid = Color(0xFFD9FF00);
  static const red = Color(0xFFFF3333);
}

final Set<int> _savedPostIds = {};

class SpodaApp extends StatelessWidget {
  const SpodaApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Spoda',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: AppColors.background,
          colorScheme: const ColorScheme.dark(primary: AppColors.acid, surface: AppColors.surface),
          fontFamily: 'Roboto',
          switchTheme: SwitchThemeData(
            thumbColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? AppColors.background : AppColors.muted),
            trackColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? AppColors.acid : AppColors.border),
          ),
        ),
        home: const AuthRouter(),
      );
}

class AuthRouter extends StatefulWidget {
  const AuthRouter({super.key});
  @override
  State<AuthRouter> createState() => _AuthRouterState();
}

class _AuthRouterState extends State<AuthRouter> {
  late Future<Map<String, dynamic>?> _session = AuthService.instance.restoreProfile();
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _linkSubscription = _appLinks.uriLinkStream.listen(_handleAuthLink);
    _appLinks.getInitialLink().then((uri) { if (uri != null) _handleAuthLink(uri); }).catchError((_) {});
  }

  Future<void> _handleAuthLink(Uri uri) async {
    if (uri.scheme != 'spoda' || uri.host != 'auth') return;
    if (uri.path == '/reset') {
      final token = uri.queryParameters['resetPasswordToken'] ?? uri.queryParameters['token'];
      if (token == null || token.isEmpty) return;
      if (mounted) Navigator.of(context).push(MaterialPageRoute(builder: (_) => ResetPasswordPage(token: token)));
      return;
    }
    if (uri.path != '/callback') return;
    final verificationToken = uri.queryParameters['token'];
    if (verificationToken != null && verificationToken.isNotEmpty) {
      try {
        await AuthService.instance.verifyEmail(verificationToken);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Email verified. You can now log in.')));
      } on AuthException catch (error) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
      return;
    }
    try {
      await AuthService.instance.storeProviderTokens(uri);
      final profile = await AuthService.instance.restoreProfile();
      if (!mounted) return;
      if (profile == null) throw const AuthException('Sign-in completed, but the profile could not be loaded.');
      setState(() {
        _session = Future.value(profile);
      });
    } on AuthException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  void dispose() { _linkSubscription?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>?>(
        future: _session,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.acid)));
          return snapshot.data == null ? const LandingPage() : const HomePage();
        },
      );
}

Future<void> _startSocialLogin(BuildContext context, String provider) async {
  final uri = Uri.https('api.spoda.ai', '/auth/$provider', {'redirect': AuthService.redirectUrl});
  try {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the sign-in page.')));
    }
  } catch (_) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the sign-in page.')));
  }
}

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});
  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  final _pager = PageController();
  int _page = 0;
  final _headings = const [
    ('AI for', 'Cricket\nAnalysis', 'Get smarter insights,\npredictions and answers for\nevery match.'),
    ('Ask anything', 'about Cricket', 'Your personal cricket assistant.\nAsk Spoda anything and get\ndata-backed insights instantly.'),
    ('Everything', 'you need to know', 'AI-powered insights across every\naspect of the game.'),
  ];
  @override
  void dispose() { _pager.dispose(); super.dispose(); }
  void _enter() => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomePage()));

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Column(children: [
            Align(alignment: Alignment.centerRight, child: TextButton(onPressed: _enter, child: const Text('Skip', style: TextStyle(color: Colors.white)))),
            Expanded(child: PageView(
              controller: _pager,
              onPageChanged: (i) => setState(() => _page = i),
              children: [
                _firstIntro(),
                _intro(_headings[1], const _ChatVisual()),
                _intro(_headings[2], const _FeatureList()),
                const _LoginPanel(),
              ],
            )),
            Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 18), child: Row(children: [
              Row(children: List.generate(4, (i) => Container(width: 6, height: 6, margin: const EdgeInsets.only(right: 4), decoration: BoxDecoration(color: i == _page ? AppColors.acid : AppColors.muted, shape: BoxShape.circle)))),
              const SizedBox(height: 30),
              if (_page > 0 && _page < 3) IconButton(onPressed: () => _pager.previousPage(duration: const Duration(milliseconds: 220), curve: Curves.easeOut), icon: const Icon(Icons.arrow_back, color: AppColors.muted)),
              IconButton.filled(onPressed: () => _page == 3 ? _enter() : _pager.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut), style: IconButton.styleFrom(backgroundColor: AppColors.acid, foregroundColor: AppColors.background), icon: Icon(_page == 3 ? Icons.check : Icons.arrow_forward)),
            ])),
          ]),
        ),
      );

  Widget _firstIntro() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/home-back.png'),
              fit: BoxFit.cover,
              alignment: Alignment.bottomRight,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_headings[0].$1, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, height: 1.08)),
              Text(_headings[0].$2, style: const TextStyle(fontSize: 34, color: AppColors.acid, fontWeight: FontWeight.w800, height: 1.08)),
              const SizedBox(height: 14),
              Text(_headings[0].$3, style: const TextStyle(color: AppColors.muted, fontSize: 16, height: 1.5)),
              const Spacer(),
            ]),
          ),
        ),
      );

  Widget _intro((String, String, String) copy, Widget artwork) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(copy.$1, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1.1)),
          Text(copy.$2, style: const TextStyle(fontSize: 24, color: AppColors.acid, fontWeight: FontWeight.w800, height: 1.1)),
          const SizedBox(height: 12),
          Text(copy.$3, style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.5)),
          const SizedBox(height: 28),
          Expanded(child: artwork),
        ]),
      );
}

class _ChatVisual extends StatelessWidget { const _ChatVisual(); @override Widget build(BuildContext context) => Container(decoration: const BoxDecoration(image: DecorationImage(image: AssetImage('assets/mobileframecontent.png'), fit: BoxFit.cover))); }

class _FeatureList extends StatelessWidget { const _FeatureList(); @override Widget build(BuildContext context) => Column(children: const [_Feature('assets/match-prediction.png', 'Match Predictions', 'Win Probability, Expected Score and more.'), SizedBox(height: 8), _Feature('assets/players-insite.png', 'Players Insights', 'Form, Stats, Matchups and Player Comparisons'), SizedBox(height: 8), _Feature('assets/key-benifit.png', 'Key Battles', 'Discover the game’s defining matchups'), SizedBox(height: 8), _Feature('assets/ask-spoda.png', 'Ask Spoda AI', 'Get instant, data-backed answers to any question.')]); }

class _Feature extends StatelessWidget { const _Feature(this.image, this.title, this.caption); final String image, title, caption; @override Widget build(BuildContext context) => Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border)), child: Row(children: [Image.asset(image, width: 32, height: 32, fit: BoxFit.contain), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.bold)), Text(caption, style: const TextStyle(color: AppColors.muted, fontSize: 11))]))])); }

class _LoginPanel extends StatelessWidget {
  const _LoginPanel({this.isLogin = false, this.onLoggedIn});

  final bool isLogin;
  final VoidCallback? onLoggedIn;

  Future<void> _emailLogin(BuildContext context) async {
    final loggedIn = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => EmailLoginPage(onLoggedIn: onLoggedIn)));
    if (loggedIn == true && context.mounted && onLoggedIn != null) {
      Navigator.of(context).pop();
      onLoggedIn!();
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(isLogin ? 'Welcome back' : 'Lets get started', style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
          Text(isLogin ? 'to Spoda AI' : 'with Spoda AI', style: const TextStyle(fontSize: 25, color: AppColors.acid, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Text(isLogin ? 'Log in to continue to your cricket insights.' : 'Create your account and unlock a smarter cricket experience.', style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 26),
          _SocialLoginButton(label: 'Continue with Google', asset: 'assets/google.png', onPressed: () => _startSocialLogin(context, 'google')),
          const SizedBox(height: 9),
          _SocialLoginButton(label: 'Continue with Facebook', asset: 'assets/facebook.png', onPressed: () => _startSocialLogin(context, 'facebook')),
          const SizedBox(height: 9),
          _SocialLoginButton(label: 'Continue with email', asset: 'assets/email.png', onPressed: () => _emailLogin(context)),
          const SizedBox(height: 14),
          const Center(child: Text('By continuing, you agree to the Terms of Service\nand acknowledge our Privacy Policy.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 10))),
          const Spacer(),
          if (!isLogin) ...[
            Center(child: RichText(text: TextSpan(style: const TextStyle(color: AppColors.muted, fontSize: 12), children: [
              const TextSpan(text: 'Already a member?  '),
              WidgetSpan(child: GestureDetector(onTap: () => _emailLogin(context), child: const Text('Log in', style: TextStyle(color: AppColors.acid, fontWeight: FontWeight.w600)))),
            ]))),
            const SizedBox(height: 8),
          ],
          Center(child: RichText(text: TextSpan(style: const TextStyle(color: AppColors.muted, fontSize: 12), children: [
            const TextSpan(text: 'New to Spoda?  '),
            WidgetSpan(child: GestureDetector(onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CreateAccountPage())), child: Text(isLogin ? 'Register' : 'Create an account', style: const TextStyle(color: AppColors.acid, fontWeight: FontWeight.w600)))),
          ]))),
          const SizedBox(height: 12),
        ]),
      );
}

class LoginPage extends StatelessWidget {
  const LoginPage({super.key, this.onLoggedIn});
  final VoidCallback? onLoggedIn;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.background,
          title: const Text('Log In'),
          leading: IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.arrow_back)),
        ),
        body: SafeArea(child: _LoginPanel(isLogin: true, onLoggedIn: onLoggedIn)),
      );
}

class _SocialLoginButton extends StatelessWidget {
  const _SocialLoginButton({required this.label, required this.asset, required this.onPressed});
  final String label;
  final String asset;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 44,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            backgroundColor: AppColors.surface,
            side: const BorderSide(color: AppColors.border),
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            foregroundColor: Colors.white,
          ),
          child: Row(children: [
            Image.asset(asset, width: 20, height: 20, fit: BoxFit.contain),
            Expanded(child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13))),
            const SizedBox(width: 20),
          ]),
        ),
      );
}

class EmailLoginPage extends StatefulWidget {
  const EmailLoginPage({super.key, this.onLoggedIn});
  final VoidCallback? onLoggedIn;
  @override
  State<EmailLoginPage> createState() => _EmailLoginPageState();
}

class _EmailLoginPageState extends State<EmailLoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _obscurePassword = true;
  bool _busy = false;

  Future<void> _submitLogin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await AuthService.instance.login(email: _username.text.trim(), password: _password.text);
      await AuthService.instance.restoreProfile();
      if (!mounted) return;
      if (widget.onLoggedIn != null) {
        Navigator.of(context).pop(true);
      } else {
        Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const HomePage()), (_) => false);
      }
    } on AuthException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() { _username.dispose(); _password.dispose(); super.dispose(); }

  InputDecoration _decoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.muted, fontSize: 12),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppColors.border), borderRadius: BorderRadius.zero),
        focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppColors.acid), borderRadius: BorderRadius.zero),
        errorBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppColors.red), borderRadius: BorderRadius.zero),
        focusedErrorBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppColors.red), borderRadius: BorderRadius.zero),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(backgroundColor: AppColors.background, leading: IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.arrow_back)), title: const Text('Back', style: TextStyle(fontSize: 14)), titleSpacing: 0),
        body: SafeArea(child: Form(
          key: _formKey,
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 22, 20, 24), children: [
            const Text('Welcome Back', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800)),
            const SizedBox(height: 5),
            const Text('Log in to continue your Spoda journey', style: TextStyle(color: AppColors.muted, fontSize: 12)),
            const SizedBox(height: 28),
            const Text('Username or email', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            TextFormField(controller: _username, keyboardType: TextInputType.emailAddress, style: const TextStyle(fontSize: 13), decoration: _decoration('yourname@example.com'), validator: (value) => value == null || value.trim().isEmpty ? 'Enter your username or email' : null),
            const SizedBox(height: 18),
            const Text('Password', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            TextFormField(controller: _password, obscureText: _obscurePassword, style: const TextStyle(fontSize: 13), decoration: _decoration('Enter your password').copyWith(suffixIcon: IconButton(onPressed: () => setState(() => _obscurePassword = !_obscurePassword), icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18, color: AppColors.muted))), validator: (value) => value == null || value.isEmpty ? 'Enter your password' : null),
            Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ForgotPasswordPage())), child: const Text('Forgot password?', style: TextStyle(color: AppColors.acid, fontSize: 11)))),
            const SizedBox(height: 8),
            SizedBox(height: 46, child: ElevatedButton(onPressed: _busy ? null : _submitLogin, style: ElevatedButton.styleFrom(backgroundColor: AppColors.acid, foregroundColor: AppColors.background, disabledBackgroundColor: AppColors.acid.withValues(alpha: .55), shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero)), child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.background)) : const Text('Log In', style: TextStyle(fontWeight: FontWeight.bold)))),
          ]),
        )),
      );
}

class CreateAccountPage extends StatefulWidget {
  const CreateAccountPage({super.key});
  @override
  State<CreateAccountPage> createState() => _CreateAccountPageState();
}

class _CreateAccountPageState extends State<CreateAccountPage> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscurePassword = true;
  bool _busy = false;

  @override
  void dispose() { _fullName.dispose(); _email.dispose(); _password.dispose(); super.dispose(); }

  Future<void> _submitRegistration() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await AuthService.instance.register(fullName: _fullName.text.trim(), email: _email.text.trim(), password: _password.text);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Check your email'),
          content: const Text('We sent you a verification link. Verify your email before logging in.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                Navigator.of(context).pop();
              },
              child: const Text('OK', style: TextStyle(color: AppColors.acid)),
            ),
          ],
        ),
      );
    } on AuthException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(child: Column(children: [
          Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomePage())), child: const Text('Skip', style: TextStyle(color: Colors.white)))),
          Expanded(child: Form(
            key: _formKey,
            child: ListView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 24), children: [
              const Text('Create your account', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1.1)),
              const SizedBox(height: 10),
              const Text('Enter your details to get started with Spoda AI', style: TextStyle(color: AppColors.muted, fontSize: 16, height: 1.5)),
              const SizedBox(height: 22),
              const Text('Full name', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 8),
              TextFormField(controller: _fullName, textCapitalization: TextCapitalization.words, style: const TextStyle(fontSize: 14), decoration: _accountInputDecoration('Jane Doe'), validator: (value) => value == null || value.trim().isEmpty ? 'Enter your full name' : null),
              const SizedBox(height: 18),
              const Text('Email address', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 8),
              TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, style: const TextStyle(fontSize: 14), decoration: _accountInputDecoration('you@example.com'), validator: (value) => value == null || !value.contains('@') ? 'Enter a valid email address' : null),
              const SizedBox(height: 18),
              const Text('Password', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 8),
              TextFormField(controller: _password, obscureText: _obscurePassword, style: const TextStyle(fontSize: 14), decoration: _accountInputDecoration('Create a password').copyWith(suffixIcon: IconButton(onPressed: () => setState(() => _obscurePassword = !_obscurePassword), icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: AppColors.muted))), validator: (value) => value == null || value.length < 8 ? 'Use at least 8 characters' : null),
              const SizedBox(height: 20),
              SizedBox(height: 48, child: ElevatedButton(onPressed: _busy ? null : _submitRegistration, style: ElevatedButton.styleFrom(backgroundColor: AppColors.acid, foregroundColor: AppColors.background, disabledBackgroundColor: AppColors.acid.withValues(alpha: .55), shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero)), child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.background)) : const Text('Create Account', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)))),
              const SizedBox(height: 24),
              const Center(child: Text('By continuing, you agree to the Terms of Service\nand acknowledge our Privacy Policy.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.6))),
            ]),
          )),
        ])),
      );
}

InputDecoration _accountInputDecoration(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppColors.border), borderRadius: BorderRadius.zero),
      focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppColors.acid), borderRadius: BorderRadius.zero),
      errorBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppColors.red), borderRadius: BorderRadius.zero),
      focusedErrorBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppColors.red), borderRadius: BorderRadius.zero),
    );

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});
  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _busy = false;
  @override
  void dispose() { _email.dispose(); super.dispose(); }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await AuthService.instance.requestPasswordReset(_email.text.trim());
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('If an account exists, a password reset link has been sent.')));
    } on AuthException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(backgroundColor: AppColors.background, title: const Text('Forgot Password', style: TextStyle(fontSize: 16))),
        body: Form(key: _formKey, child: ListView(padding: const EdgeInsets.all(20), children: [
          const SizedBox(height: 12),
          const Text('Reset your password', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('Enter the email address associated with your Spoda account.', style: TextStyle(color: AppColors.muted, height: 1.5)),
          const SizedBox(height: 24),
          const Text('Email address'), const SizedBox(height: 8),
          TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: _accountInputDecoration('you@example.com'), validator: (v) => v == null || !v.contains('@') ? 'Enter a valid email address' : null),
          const SizedBox(height: 18),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _busy ? null : _send,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.acid,
                foregroundColor: AppColors.background,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              ),
              child: _busy
                  ? const CircularProgressIndicator(color: AppColors.background)
                  : const Text('Send reset link'),
            ),
          ),
        ])),
      );
}

class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key, required this.token});
  final String token;
  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  bool _busy = false;
  final bool _verified = true;
  String? _error;
  @override
  void dispose() { _password.dispose(); super.dispose(); }

  Future<void> _change() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await AuthService.instance.changePassword(token: widget.token, password: _password.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password changed. You can now log in.')));
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on AuthException catch (error) { if (mounted) setState(() => _error = error.message); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(backgroundColor: AppColors.background, title: const Text('Set New Password', style: TextStyle(fontSize: 16))),
        body: _error != null ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center))) : !_verified ? const Center(child: CircularProgressIndicator(color: AppColors.acid)) : Form(key: _formKey, child: ListView(padding: const EdgeInsets.all(20), children: [
          const Text('Choose a new password', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 20),
          TextFormField(controller: _password, obscureText: true, decoration: _accountInputDecoration('At least 8 characters'), validator: (v) => v == null || v.length < 8 ? 'Use at least 8 characters' : null),
          const SizedBox(height: 18),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _busy ? null : _change,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.acid,
                foregroundColor: AppColors.background,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              ),
              child: _busy
                  ? const CircularProgressIndicator(color: AppColors.background)
                  : const Text('Change password'),
            ),
          ),
        ])),
      );
}

class MatchData {
  const MatchData({required this.raw, this.group = 'today'});
  final Map<String, dynamic> raw;
  final String group;
  String get title => _first(raw, ['title', 'name', 'match_name', 'matchName', 'short_title', 'shortTitle']) ?? '${_team('teamName1', 'Team 1')} vs ${_team('teamName2', 'Team 2')}';
  String get status => _first(raw, ['status', 'state', 'match_status', 'matchStatus', 'status_str']) ?? (group == 'previous' ? 'Completed' : group == 'tomorrow' ? 'Upcoming' : 'Today');
  String get venue => _first(raw, ['venue', 'ground', 'date', 'start_time', 'startTime', 'startDate']) ?? '';
  String get score => _first(raw, ['score', 'result', 'subtitle', 'competition', 'seriesName', 'series_name']) ?? '';
  String get matchId => _first(raw, ['matchId', 'match_id', 'id']) ?? '';
  String teamName(String suffix, {Map<String, dynamic>? scorecard}) {
    final scorecardTeam = _scorecardTeam(scorecard, suffix);
    if (scorecardTeam?['short_name'] != null && scorecardTeam!['short_name'].toString().isNotEmpty) return scorecardTeam['short_name'].toString();
    if (scorecardTeam?['name'] != null && scorecardTeam!['name'].toString().isNotEmpty) return scorecardTeam['name'].toString();
    final value = raw['team$suffix'];
    if (value is Map) return (value['shortName'] ?? value['short_name'] ?? value['name'] ?? 'Team $suffix').toString();
    return (raw['teamName$suffix'] ?? raw['team$suffix Name'] ?? 'Team $suffix').toString();
  }
  String teamScore(String suffix, {Map<String, dynamic>? scorecard}) {
    final value = _scorecardTeam(scorecard, suffix)?['scores'];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is num) return value.toString();
    return 'Yet to bat';
  }
  String teamOvers(String suffix, {Map<String, dynamic>? scorecard}) {
    final value = _scorecardTeam(scorecard, suffix)?['overs'];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is num) return value.toString();
    return '';
  }
  String scoreFrom(Map<String, dynamic>? scorecard) {
    final value = _findScorecardValue(scorecard, 'scores_full');
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is List) return value.map((item) => item.toString()).where((item) => item.trim().isNotEmpty).join('\n');
    if (value is Map) return value.values.map((item) => item.toString()).where((item) => item.trim().isNotEmpty).join('\n');
    return score;
  }
  String seriesName(Map<String, dynamic>? scorecard) {
    final value = _findScorecardValue(scorecard, 'format_str');
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return tournament;
  }
  String matchFormatLabel(Map<String, dynamic>? scorecard) => '[${seriesName(scorecard)}]';
  Object? _findScorecardValue(Object? value, String key) {
    if (value is Map) {
      for (final entry in value.entries) {
        if (entry.key.toString().toLowerCase() == key.toLowerCase()) return entry.value;
      }
      for (final child in value.values) {
        final found = _findScorecardValue(child, key);
        if (found != null) return found;
      }
    } else if (value is List) {
      for (final child in value) {
        final found = _findScorecardValue(child, key);
        if (found != null) return found;
      }
    }
    return null;
  }
  String? teamFlag(String suffix, {Map<String, dynamic>? scorecard}) {
    final scorecardTeam = _scorecardTeam(scorecard, suffix);
    final scorecardLogo = scorecardTeam?['logo_url'];
    if (scorecardLogo is String && scorecardLogo.isNotEmpty) return scorecardLogo;
    final value = raw['team$suffix'];
    if (value is Map) return (value['thumb_url'] ?? value['thumbUrl'] ?? value['flag']).toString();
    return _first(raw, ['team${suffix}ThumbUrl', 'team${suffix}_thumb_url']);
  }
  Map<String, dynamic>? _scorecardTeam(Map<String, dynamic>? scorecard, String side) {
    if (scorecard == null) return null;
    final key = side.toLowerCase() == 'a' ? 'teama' : 'teamb';
    Map<String, dynamic>? find(Object? value) {
      if (value is Map) {
        for (final entry in value.entries) {
          if (entry.key.toString().toLowerCase() == key && entry.value is Map) return Map<String, dynamic>.from(entry.value as Map);
        }
        for (final entry in value.values) {
          final found = find(entry);
          if (found != null) return found;
        }
      } else if (value is List) {
        for (final item in value) {
          final found = find(item);
          if (found != null) return found;
        }
      }
      return null;
    }
    return find(scorecard);
  }
  String get tournament => _first(raw, ['seriesName', 'series_name', 'competition', 'title', 'name']) ?? 'MATCH';
  DateTime? get startDate {
    final value = _first(raw, ['startDate', 'start_date', 'dateTimeGMT', 'date', 'start_time', 'startTime']);
    return value == null ? null : DateTime.tryParse(value);
  }
  String _team(String key, String fallback) { final value = raw[key]; if (value is Map) return (value['name'] ?? value['shortName'] ?? value['short_name'] ?? fallback).toString(); return value?.toString() ?? fallback; }
  static String? _first(Map<String, dynamic> data, List<String> keys) { for (final key in keys) { final value = data[key]; if (value is String && value.trim().isNotEmpty) return value; if (value is num) return value.toString(); } return null; }
  static List<MatchData> decode(Object? value) {
    if (value is List) return value.whereType<Map>().map((m) => MatchData(raw: Map<String, dynamic>.from(m))).toList();
    if (value is Map) {
      final groups = <MatchData>[];
      for (final entry in const [
        ('liveMatches', 'live'),
        ('live', 'live'),
        ('todaysMatches', 'today'),
        ('todayMatches', 'today'),
        ('tomorrowsMatches', 'tomorrow'),
        ('upcomingMatches', 'tomorrow'),
        ('upcoming', 'tomorrow'),
        ('previousMatches', 'previous'),
        ('completedMatches', 'previous'),
        ('completed', 'previous'),
      ]) {
        final rows = value[entry.$1];
        if (rows is List) {
          groups.addAll(rows.whereType<Map>().map((m) => MatchData(raw: Map<String, dynamic>.from(m), group: entry.$2)));
        }
      }
      if (groups.isNotEmpty) return groups;
      for (final key in ['matches', 'data', 'results', 'items']) {
        if (value[key] is List) return decode(value[key]);
      }
    }
    return [];
  }
}

class HomePage extends StatefulWidget { const HomePage({super.key}); @override State<HomePage> createState() => _HomePageState(); }
class _HomePageState extends State<HomePage> {
  int _tab = 0;
  int _matchStatus = 1;
  int _filter = 0;
  final _filters = const ['All', 'Odds', 'T20s', "Int’l", "Men’s", "Women’s"];
  final _matchStatuses = const ['Live', 'Upcoming', 'Completed'];
  late Future<List<MatchData>> _matches = _loadMatches();
  late Future<List<BlogPost>> _posts = _loadPosts(4, 1);
  final Map<String, Future<Map<String, dynamic>?>> _scorecardRequests = {};
  Future<List<BlogPost>> _loadPosts(int count, int page) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse('http://140.238.244.171:8083/wp-json/wp/v2/posts?_embed&per_page=$count&page=$page'));
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await req.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) throw HttpException('Posts returned ${response.statusCode}');
      final decoded = jsonDecode(body);
      if (decoded is! List) return [];
      return decoded.whereType<Map>().map((row) => BlogPost.fromJson(Map<String, dynamic>.from(row))).toList();
    } finally { client.close(force: true); }
  }
  Future<List<BlogPost>> _loadSavedPosts(Set<int> ids) async {
    if (ids.isEmpty) return const [];
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final uri = Uri.http('140.238.244.171:8083', '/wp-json/wp/v2/posts', {'include': ids.join(','), '_embed': ''});
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) throw HttpException('Saved posts returned ${response.statusCode}');
      final decoded = jsonDecode(body);
      return decoded is List ? decoded.whereType<Map>().map((row) => BlogPost.fromJson(Map<String, dynamic>.from(row))).toList() : const [];
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>?> _loadScorecard(MatchData match) => _scorecardRequests.putIfAbsent(match.matchId, () async {
    if (match.matchId.isEmpty) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(Uri.parse('https://api.spoda.ai/match-scorecard?matchId=${Uri.encodeQueryComponent(match.matchId)}'));
      final response = await req.close();
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final payload = jsonDecode(await response.transform(utf8.decoder).join());
      return payload is Map ? Map<String, dynamic>.from(payload) : null;
    } catch (_) { return null; } finally { client.close(force: true); }
  });
  bool _containsLiveStatus(Object? value) {
    if (value is Map) {
      for (final entry in value.entries) {
        if (entry.key.toString().toLowerCase() == 'status_str' && entry.value.toString().trim().toLowerCase() == 'live') return true;
        if (_containsLiveStatus(entry.value)) return true;
      }
    } else if (value is List) return value.any(_containsLiveStatus);
    return false;
  }
  List<MatchData> _ordered(List<MatchData> rows) {
    final result = [...rows];
    result.sort((a, b) => (a.startDate ?? DateTime(2100)).compareTo(b.startDate ?? DateTime(2100)));
    return result;
  }
  Future<List<MatchData>> _loadMatches() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse('https://api.spoda.ai/match-overview/matches'));
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await req.close();
      final text = await response.transform(utf8.decoder).join();
      debugPrint('[matches-api] HTTP ${response.statusCode}');
      debugPrint('[matches-api] Raw response: $text');
      if (response.statusCode < 200 || response.statusCode >= 300) throw HttpException('Server returned ${response.statusCode}');
      final matches = MatchData.decode(jsonDecode(text));
      debugPrint('[matches-api] Loaded ${matches.length} rows');
      for (var i = 0; i < matches.length; i++) {
        debugPrint('[matches-api] row ${i + 1}: ${jsonEncode(matches[i].raw)}');
      }
      return matches;
    } finally {
      client.close(force: true);
    }
  }
  
  bool _isLive(MatchData m) => m.group == 'live' || '${m.status} ${m.raw}'.toLowerCase().contains(RegExp(r'live|in.?progress|innings|stumps'));
  bool _isDone(MatchData m) => m.group == 'previous' || '${m.status} ${m.raw}'.toLowerCase().contains(RegExp(r'complete|finished|result|won|abandoned'));
  List<MatchData> _filtered(List<MatchData> list) {
    final statusMatches = switch (_matchStatus) {
      0 => list.where(_isLive).toList(),
      1 => list.where((m) => !_isLive(m) && !_isDone(m)).toList(),
      _ => list.where(_isDone).toList(),
    };
    if (_filter == 0) return statusMatches;
    final filter = _filters[_filter].replaceAll('’', '').toLowerCase();
    return statusMatches.where((m) => '${m.raw} ${m.score} ${m.title}'.toLowerCase().contains(filter)).toList();
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(backgroundColor: AppColors.background, shape: const Border(bottom: BorderSide(color: AppColors.acid, width: 1)), title: Image.asset('assets/logo_spoda.png', height: 24, fit: BoxFit.contain), centerTitle: true, leading: IconButton(onPressed: _openMenu, icon: const Icon(Icons.menu, color: AppColors.acid))),
    body: _tab == 0 ? _homeDashboard() : _tab == 1 ? _matchPage() : _tab == 2 ? BlogListPage(preloaded: _posts) : ProfilePage(postsLoader: _loadSavedPosts),
    bottomNavigationBar: NavigationBarTheme(
      data: NavigationBarThemeData(
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>((states) =>
            IconThemeData(color: states.contains(WidgetState.selected) ? const Color(0xFFE7FF00) : AppColors.muted)),
      ),
      child: NavigationBar(
        backgroundColor: AppColors.surface,
        indicatorColor: Colors.transparent,
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
        NavigationDestination(icon: Icon(Icons.emoji_events_outlined), label: 'Matches'),
        NavigationDestination(icon: Icon(Icons.newspaper_outlined), label: 'Blogs & News'),
        NavigationDestination(icon: Icon(Icons.account_circle_outlined), label: 'Profile'),
      ],
      ),
    ),
  );
  Widget _homeDashboard() => FutureBuilder<List<MatchData>>(
    future: _matches,
    builder: (context, matchSnapshot) => FutureBuilder<List<BlogPost>>(
      future: _posts,
      builder: (context, postSnapshot) => RefreshIndicator(
        color: AppColors.acid,
        onRefresh: () async { final matches = _loadMatches(); final posts = _loadPosts(4, 1); setState(() { _matches = matches; _posts = posts; _scorecardRequests.clear(); }); await Future.wait([matches, posts]); },
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
          if (matchSnapshot.hasData)
            _liveSlider(_ordered((matchSnapshot.data ?? []).where((m) => m.group == 'live' || m.group == 'today' || _isLive(m)).toList())),
          const SizedBox(height: 24), _sectionHeader('Upcoming', () => setState(() { _tab = 1; _matchStatus = 1; })),
          if (matchSnapshot.connectionState == ConnectionState.waiting) const SizedBox(height: 100, child: Center(child: CircularProgressIndicator(color: AppColors.acid)))
          else ..._ordered((matchSnapshot.data ?? []).where((m) => !_isLive(m) && !_isDone(m) && (m.startDate == null || m.startDate!.isAfter(DateTime.now()))).toList()).map(_upcomingCard),
          const SizedBox(height: 16), _sectionHeader('News and Blogs', () => setState(() => _tab = 2)),
          if (postSnapshot.connectionState == ConnectionState.waiting) const SizedBox(height: 120, child: Center(child: CircularProgressIndicator(color: AppColors.acid)))
          else if (postSnapshot.hasError) TextButton(onPressed: () => setState(() { _posts = _loadPosts(4, 1); }), child: const Text('Could not load posts. Tap to retry.'))
          else ..._blogPreviews(postSnapshot.data ?? []),
        ]),
      ),
    ),
  );
  Widget _sectionHeader(String title, VoidCallback action, {double topPadding = 18}) => Padding(padding: EdgeInsets.only(top: topPadding, bottom: 14), child: Row(children: [Expanded(child: Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800))), InkWell(onTap: action, child: const Row(children: [Text('View All', style: TextStyle(fontSize: 12, color: AppColors.muted)), SizedBox(width: 4), Icon(Icons.chevron_right, size: 20)]))]));
  Widget _liveSlider(List<MatchData> matches) {
    if (matches.isEmpty) return const SizedBox.shrink();
    return FutureBuilder<List<Map<String, dynamic>?>>(
      future: Future.wait(matches.map(_loadScorecard)),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const SizedBox.shrink();
        final cards = <(MatchData, Map<String, dynamic>?)>[];
        for (var i = 0; i < matches.length; i++) {
          final scorecard = snapshot.data != null && i < snapshot.data!.length ? snapshot.data![i] : null;
          if (_isLive(matches[i]) || (scorecard != null && _containsLiveStatus(scorecard))) cards.add((matches[i], scorecard));
        }
        if (cards.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sectionHeader('Live Matches', () => setState(() { _tab = 1; _matchStatus = 0; }), topPadding: 6),
          SizedBox(height: 275, child: cards.length == 1
              ? Center(child: SizedBox(
                  width: MediaQuery.sizeOf(context).width * .82,
                  child: _LiveMatchCard(
                    match: cards.single.$1,
                    live: true,
                    scorecard: cards.single.$2,
                    onTap: () => _openMatchDetails(cards.single.$1, cards.single.$2),
                  ),
                ))
              : ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: cards.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) => SizedBox(
              width: MediaQuery.sizeOf(context).width * .82,
              child: _LiveMatchCard(
                match: cards[i].$1,
                live: true,
                scorecard: cards[i].$2,
                onTap: () => _openMatchDetails(cards[i].$1, cards[i].$2),
              ),
            ),
          )),
          const SizedBox(height: 8),
        ]);
      },
    );
  }
  Widget _upcomingCard(MatchData match) => FutureBuilder<Map<String, dynamic>?>(future: _loadScorecard(match), builder: (context, snapshot) => _upcomingCardAligned(match, snapshot.data));
  Widget _upcomingCardAligned(MatchData match, Map<String, dynamic>? scorecard) => InkWell(
        onTap: () => _openMatchDetails(match, scorecard),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border)),
          child: Column(children: [
            Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(match.matchFormatLabel(scorecard), style: const TextStyle(color: AppColors.acid, fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _alignedUpcomingTeam(match, 'A', scorecard)),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('vs', style: TextStyle(color: AppColors.muted))),
                Expanded(child: _alignedUpcomingTeam(match, 'B', scorecard)),
                const SizedBox(width: 12), Container(width: 1, height: 38, color: AppColors.border), const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text(_timeFor(match), style: const TextStyle(color: AppColors.muted, fontSize: 12)), Text(_dateLabel(match), style: const TextStyle(color: AppColors.muted, fontSize: 12))]),
              ]),
            ])),
            Container(color: const Color(0xFF111111), padding: const EdgeInsets.all(12), child: Row(children: [
              Expanded(child: Text(_isLive(match) ? 'Live match updates and score' : _isDone(match) ? 'Match result and scorecard available' : 'Match prediction and insights available', style: const TextStyle(fontSize: 12, color: Colors.white70))),
              TextButton(onPressed: () => _openMatchDetails(match, scorecard), style: TextButton.styleFrom(backgroundColor: AppColors.acid, foregroundColor: Colors.black, shape: const RoundedRectangleBorder()), child: Text(_isLive(match) ? 'Live Match' : _isDone(match) ? 'Scorecard ›' : 'Prediction ›', style: const TextStyle(fontWeight: FontWeight.bold))),
            ])),
          ]),
        ),
      );
  Widget _alignedUpcomingTeam(MatchData match, String side, Map<String, dynamic>? scorecard) {
    final right = side == 'B';
    final logo = _teamBadge(match, side, scorecard);
    return Row(mainAxisAlignment: right ? MainAxisAlignment.end : MainAxisAlignment.start, children: [
      if (!right) ...[logo, const SizedBox(width: 5)],
      Flexible(child: Text(match.teamName(side, scorecard: scorecard), textAlign: right ? TextAlign.right : TextAlign.left, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
      if (right) ...[const SizedBox(width: 5), logo],
    ]);
  }
  void _openMatchDetails(MatchData match, [Map<String, dynamic>? scorecard]) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MatchDetailPage(match: match, scorecard: scorecard, matchesFuture: _matches)));
  Widget _upcomingCardContent(MatchData match, Map<String, dynamic>? scorecard) => InkWell(
        onTap: () => _openMatchDetails(match, scorecard),
        child: Container(margin: const EdgeInsets.only(bottom: 10), decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border)), child: Column(children: [Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(match.matchFormatLabel(scorecard), style: const TextStyle(color: AppColors.acid, fontSize: 11, fontWeight: FontWeight.bold)), const SizedBox(height: 12), Row(children: [Expanded(child: Row(children: [_teamBadge(match, 'A', scorecard), const SizedBox(width: 8), Flexible(child: Text(match.teamName('A', scorecard: scorecard), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))), const Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('vs', style: TextStyle(color: AppColors.muted))), _teamBadge(match, 'B', scorecard), const SizedBox(width: 8), Flexible(child: Text(match.teamName('B', scorecard: scorecard), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)))])), Container(width: 1, height: 38, color: AppColors.border), const SizedBox(width: 12), Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text(_timeFor(match), style: const TextStyle(color: AppColors.muted, fontSize: 12)), Text(_dateLabel(match), style: const TextStyle(color: AppColors.muted, fontSize: 12))])])])), Container(color: const Color(0xFF111111), padding: const EdgeInsets.all(12), child: Row(children: [const Expanded(child: Text('•  Match prediction and insights available', style: TextStyle(fontSize: 12, color: Colors.white70))), TextButton(onPressed: () => _openMatchDetails(match, scorecard), style: TextButton.styleFrom(backgroundColor: AppColors.acid, foregroundColor: Colors.black, shape: const RoundedRectangleBorder()), child: const Text('Prediction  ›', style: TextStyle(fontWeight: FontWeight.bold)))]) )])));
  String _dateLabel(MatchData match) {
    final date = match.startDate?.toLocal();
    if (date == null) return 'Upcoming';
    final now = DateTime.now();
    if (date.year == now.year && date.month == now.month && date.day == now.day) return 'Today';
    final tomorrow = now.add(const Duration(days: 1));
    if (date.year == tomorrow.year && date.month == tomorrow.month && date.day == tomorrow.day) return 'Tomorrow';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
  List<Widget> _blogPreviews(List<BlogPost> posts) { if (posts.isEmpty) return [const Text('No posts found.', style: TextStyle(color: AppColors.muted))]; return [if (posts.isNotEmpty) _featuredPost(posts.first), ...posts.skip(1).map((post) => _postTile(post))]; }
  Widget _featuredPost(BlogPost post) => InkWell(
        onTap: () => _showPost(post),
        child: Container(
          height: 220,
          margin: const EdgeInsets.only(bottom: 18),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            image: post.image.isEmpty ? null : DecorationImage(image: NetworkImage(post.image), fit: BoxFit.cover, onError: (_, _) {}),
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x66000000), Color(0x14000000), Color(0xF0000000)],
                stops: [0, .35, 1],
              ),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _blogBadge(),
              const Spacer(),
              Text(post.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 6),
              Text(post.excerpt, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.white70)),
              const SizedBox(height: 12),
              Row(children: [
                const Icon(Icons.access_time_outlined, size: 16, color: AppColors.muted),
                const SizedBox(width: 8),
                const Text('8 min read', style: TextStyle(color: AppColors.muted, fontSize: 11)),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('·', style: TextStyle(color: AppColors.muted))),
                Text(_timeAgo(post.publishedAt), style: const TextStyle(color: AppColors.muted, fontSize: 11)),
              ]),
            ]),
          ),
        ),
      );

  Widget _postTile(BlogPost post) => InkWell(
        onTap: () => _showPost(post),
        child: Container(
          height: 184,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border)),
          child: Row(children: [
            if (post.image.isNotEmpty)
              ClipRRect(
                child: Image.network(post.image, width: 110, height: 160, fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(width: 110, height: 160, color: AppColors.border, child: const Icon(Icons.image))),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [_blogBadge(), const Spacer(), Text(_timeAgo(post.publishedAt), style: const TextStyle(color: AppColors.muted, fontSize: 10))]),
                const SizedBox(height: 6),
                Text(post.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(post.excerpt, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                const Spacer(),
                Align(alignment: Alignment.centerRight, child: _savePostButton(post)),
              ]),
            ),
          ]),
        ),
      );

  Widget _blogBadge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: const BoxDecoration(color: Color(0x99102A20)),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.menu_book_outlined, size: 16, color: Color(0xFF46C68A)),
          SizedBox(width: 6),
          Text('Blogs', style: TextStyle(color: Color(0xFF46C68A), fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _savePostButton(BlogPost post) => InkWell(
        onTap: () => setState(() { _savedPostIds.contains(post.id) ? _savedPostIds.remove(post.id) : _savedPostIds.add(post.id); }),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(_savedPostIds.contains(post.id) ? Icons.bookmark : Icons.bookmark_border, size: 18,
              color: _savedPostIds.contains(post.id) ? AppColors.acid : AppColors.muted),
        ),
      );
  void _showPost(BlogPost post) => showDialog<void>(context: context, builder: (context) => Dialog(backgroundColor: AppColors.surface, child: SizedBox(height: MediaQuery.sizeOf(context).height * .8, child: Column(children: [if (post.image.isNotEmpty) Image.network(post.image, height: 200, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()), Padding(padding: const EdgeInsets.all(16), child: Text(post.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20))), Expanded(child: SingleChildScrollView(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(post.content))), TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))]))));
  String _timeFor(MatchData m) { final d = m.startDate?.toLocal(); if (d == null) return '04:00 PM'; final hour = d.hour % 12 == 0 ? 12 : d.hour % 12; return '${hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}'; }
  Widget _teamBadge(MatchData match, String suffix, [Map<String, dynamic>? scorecard]) { final url = match.teamFlag(suffix, scorecard: scorecard); return url == null || url.isEmpty ? const Icon(Icons.shield, size: 24, color: AppColors.muted) : ClipOval(child: Image.network(url, width: 24, height: 24, fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.shield, size: 24, color: AppColors.muted))); }
  Widget _matchPage() => Column(
        children: [
          SizedBox(
            height: 54,
            child: Row(
              children: List.generate(_matchStatuses.length, (i) => Expanded(
                child: InkWell(
                  onTap: () => setState(() => _matchStatus = i),
                  child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    Expanded(child: Center(child: Text(_matchStatuses[i], style: TextStyle(color: _matchStatus == i ? Colors.white : AppColors.muted, fontWeight: _matchStatus == i ? FontWeight.w700 : FontWeight.w500)))),
                    Container(height: 2, color: _matchStatus == i ? AppColors.acid : Colors.transparent),
                  ]),
                ),
              )),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              itemCount: _filters.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) => ChoiceChip(
                label: Text(_filters[i]),
                selected: _filter == i,
                onSelected: (_) => setState(() => _filter = i),
                selectedColor: AppColors.acid,
                visualDensity: VisualDensity.compact,
                labelStyle: TextStyle(color: _filter == i ? AppColors.background : AppColors.muted),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<MatchData>>(
              future: _matches,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: AppColors.acid));
                }
                if (snapshot.hasError) {
                  return _empty('Could not load matches. Check your connection and try again.', retry: true);
                }
                final filteredMatches = _filtered(snapshot.data ?? []);
                final matches = _matchStatus == 1 ? _ordered(filteredMatches) : filteredMatches;
                if (matches.isEmpty) {
                  final noMatchesAtAll = snapshot.data?.isEmpty ?? true;
                  return _empty(noMatchesAtAll ? 'No matches are available right now.' : 'No matches in this category.');
                }
                return RefreshIndicator(
                  color: AppColors.acid,
                  onRefresh: () async {
                    final future = _loadMatches();
                    setState(() { _matches = future; });
                    await future;
                  },
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                    children: [
                      ...matches.map((m) => FutureBuilder<Map<String, dynamic>?>(
                        future: _loadScorecard(m),
                        builder: (context, scorecard) => _upcomingCardAligned(m, scorecard.data),
                      )),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      );
  Widget _empty(String text, {bool retry = false}) => Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)), if (retry) TextButton(onPressed: () => setState(() { _matches = _loadMatches(); }), child: const Text('Try again'))])));
  void _openMenu() => showGeneralDialog<void>(context: context, barrierDismissible: true, barrierLabel: 'Close menu', barrierColor: Colors.black54, transitionDuration: const Duration(milliseconds: 200), pageBuilder: (_, _, _) => Align(alignment: Alignment.centerRight, child: SizedBox(width: MediaQuery.sizeOf(context).width * .84, height: double.infinity, child: _SideMenu(onMatches: () { Navigator.of(context).pop(); setState(() => _tab = 1); }))), transitionBuilder: (_, animation, _, child) => SlideTransition(position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(animation), child: child));
}

class BlogPost {
  const BlogPost({required this.id, required this.title, required this.excerpt, required this.content, required this.image, required this.publishedAt});
  final int id;
  final String title, excerpt, content, image;
  final DateTime? publishedAt;

  factory BlogPost.fromJson(Map<String, dynamic> json) {
    String clean(Object? value) => value is Map
        ? (value['rendered'] ?? '').toString().replaceAll(RegExp('<[^>]*>'), '').replaceAll('&amp;', '&').replaceAll('&#8217;', '’').trim()
        : (value ?? '').toString();
    final embedded = json['_embedded'];
    final media = embedded is Map && embedded['wp:featuredmedia'] is List && (embedded['wp:featuredmedia'] as List).isNotEmpty
        ? (embedded['wp:featuredmedia'] as List).first
        : null;
    return BlogPost(
      id: int.tryParse('${json['id']}') ?? 0,
      title: clean(json['title']),
      excerpt: clean(json['excerpt']),
      content: clean(json['content']),
      image: (json['thumbnailUrl'] ?? (media is Map ? media['source_url'] : null) ?? '').toString(),
      publishedAt: DateTime.tryParse('${json['date_gmt'] ?? json['date'] ?? ''}')?.toUtc(),
    );
  }
}

String _timeAgo(DateTime? publishedAt) {
  if (publishedAt == null) return 'Date unavailable';
  final elapsed = DateTime.now().toUtc().difference(publishedAt.toUtc());
  if (elapsed.isNegative || elapsed.inMinutes < 1) return 'Just now';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes}m ago';
  if (elapsed.inDays < 1) return '${elapsed.inHours}h ago';
  if (elapsed.inDays < 7) return '${elapsed.inDays}d ago';
  if (elapsed.inDays < 30) return '${elapsed.inDays ~/ 7}w ago';
  if (elapsed.inDays < 365) return '${elapsed.inDays ~/ 30}mo ago';
  return '${elapsed.inDays ~/ 365}y ago';
}

class BlogListPage extends StatefulWidget {
  const BlogListPage({super.key, required this.preloaded});
  final Future<List<BlogPost>> preloaded;
  @override State<BlogListPage> createState() => _BlogListPageState();
}

class _BlogListPageState extends State<BlogListPage> {
  final _scroll = ScrollController();
  final List<BlogPost> _posts = [];
  var _loading = true;
  var _hasMore = true;
  var _page = 1;

  @override void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadFirstPage();
  }

  Future<void> _loadFirstPage() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(Uri.parse('http://140.238.244.171:8083/wp-json/wp/v2/posts?_embed&per_page=10&page=1'));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) throw HttpException('Posts returned ${response.statusCode}');
      final data = jsonDecode(body);
      final posts = data is List ? data.whereType<Map>().map((e) => BlogPost.fromJson(Map<String, dynamic>.from(e))).toList() : <BlogPost>[];
      if (mounted) setState(() { _posts.addAll(posts); _hasMore = posts.length == 10; _loading = false; });
    } catch (_) {
      try {
        final posts = await widget.preloaded;
        if (mounted) setState(() { _posts.addAll(posts); _hasMore = false; _loading = false; });
      } catch (_) { if (mounted) setState(() => _loading = false); }
    } finally { client.close(force: true); }
  }

  void _onScroll() { if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 300) _loadNextPage(); }

  Future<void> _loadNextPage() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    final nextPage = _page + 1;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(Uri.parse('http://140.238.244.171:8083/wp-json/wp/v2/posts?_embed&per_page=10&page=$nextPage'));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) throw HttpException('Posts returned ${response.statusCode}');
      final data = jsonDecode(body);
      final posts = data is List ? data.whereType<Map>().map((e) => BlogPost.fromJson(Map<String, dynamic>.from(e))).toList() : <BlogPost>[];
      if (mounted) setState(() { _page = nextPage; _posts.addAll(posts); _hasMore = posts.length == 10; _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
    finally { client.close(force: true); }
  }

  @override void dispose() { _scroll.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) => ListView.builder(
    controller: _scroll,
    padding: const EdgeInsets.all(16),
    itemCount: _posts.length + (_loading || _hasMore ? 1 : 0),
    itemBuilder: (context, index) {
      if (index == _posts.length) return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator(color: AppColors.acid)));
      final post = _posts[index];
      return InkWell(
        onTap: () => showDialog<void>(context: context, builder: (context) => Dialog(backgroundColor: AppColors.surface, child: SizedBox(height: MediaQuery.sizeOf(context).height * .82, child: Column(children: [if (post.image.isNotEmpty) Image.network(post.image, height: 200, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()), Padding(padding: const EdgeInsets.all(16), child: Text(post.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20))), Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Text(post.content))), TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))])))),
        child: Container(
          height: 184,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border)),
          child: Row(children: [
            if (post.image.isNotEmpty)
              ClipRRect(
                child: Image.network(post.image, width: 110, height: 160, fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(width: 110, height: 160, color: AppColors.border, child: const Icon(Icons.image))),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: const BoxDecoration(color: Color(0x99102A20)),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.menu_book_outlined, size: 16, color: Color(0xFF46C68A)),
                      SizedBox(width: 6),
                      Text('Blogs', style: TextStyle(color: Color(0xFF46C68A), fontSize: 13, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                  const Spacer(),
                  Text(_timeAgo(post.publishedAt), style: const TextStyle(color: AppColors.muted, fontSize: 10)),
                ]),
                const SizedBox(height: 6),
                Text(post.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(post.excerpt, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                const Spacer(),
                Align(
                  alignment: Alignment.centerRight,
                  child: InkWell(
                    onTap: () => setState(() { _savedPostIds.contains(post.id) ? _savedPostIds.remove(post.id) : _savedPostIds.add(post.id); }),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(_savedPostIds.contains(post.id) ? Icons.bookmark : Icons.bookmark_border, size: 18,
                          color: _savedPostIds.contains(post.id) ? AppColors.acid : AppColors.muted),
                    ),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      );
    },
  );
}

class _LiveMatchCard extends StatefulWidget {
  const _LiveMatchCard({required this.match, required this.live, required this.onTap, this.scorecard});
  final MatchData match;
  final bool live;
  final VoidCallback onTap;
  final Map<String, dynamic>? scorecard;
  @override
  State<_LiveMatchCard> createState() => _LiveMatchCardState();
}

class _LiveMatchCardState extends State<_LiveMatchCard> {
  static const _storage = FlutterSecureStorage();
  Timer? _timer;
  String? _momentum;
  bool _loading = true;
  @override
  void initState() { super.initState(); _refresh(); _timer = Timer.periodic(const Duration(minutes: 5), (_) => _refresh()); }
  @override
  void didUpdateWidget(covariant _LiveMatchCard oldWidget) { super.didUpdateWidget(oldWidget); if (oldWidget.match.matchId != widget.match.matchId) _refresh(); }
  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  Future<void> _refresh() async {
    final id = widget.match.matchId;
    if (id.isEmpty) { if (mounted) setState(() => _loading = false); return; }
    try {
      final key = 'match_win_probability_$id';
      final previous = await _storage.read(key: key);
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
      Map<String, dynamic>? response;
      try {
        final request = await client.getUrl(Uri.parse('https://www.spoda.ai/api/overend-predictions?matchId=${Uri.encodeQueryComponent(id)}'));
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        final result = await request.close();
        if (result.statusCode >= 200 && result.statusCode < 300) {
          final data = jsonDecode(await result.transform(utf8.decoder).join());
          if (data is Map) response = Map<String, dynamic>.from(data);
        }
      } finally { client.close(force: true); }
      if (response == null) return;
      final current = _extract(response)..sort((a, b) => b.value.compareTo(a.value));
      if (current.isEmpty) return;
      final old = previous == null ? <String, double>{} : _extract(jsonDecode(previous)).fold<Map<String, double>>({}, (map, item) => map..[item.key.toLowerCase()] = item.value);
      final leader = current.first;
      final oldValue = old[leader.key.toLowerCase()];
      final delta = oldValue == null ? null : leader.value - oldValue;
      final pct = (delta ?? leader.value).toStringAsFixed((delta ?? leader.value) % 1 == 0 ? 0 : 1);
      final message = delta == null
          ? '${leader.key} — $pct% chance of winning'
          : delta > 0
              ? '${leader.key} chances of winning have been increased by $pct%'
              : delta < 0
                  ? '${leader.key} chances of winning have decreased by ${delta.abs().toStringAsFixed(delta.abs() % 1 == 0 ? 0 : 1)}%'
                  : '${leader.key} — ${leader.value.toStringAsFixed(0)}% chance of winning';
      await _storage.write(key: key, value: jsonEncode(response));
      if (mounted) setState(() { _momentum = message; _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  List<MapEntry<String, double>> _extract(Object? input) {
    final found = <MapEntry<String, double>>[];
    double? number(Object? x) {
      if (x is num) return x.toDouble();
      if (x is String) return double.tryParse(x.replaceAll('%', '').trim());
      return null;
    }
    String? teamLabel(Object? value) {
      if (value is Map) {
        return (value['name'] ?? value['short_name'] ?? value['shortName'] ?? value['team_name'])?.toString();
      }
      if (value is String && value.trim().isNotEmpty) return value.trim();
      return null;
    }
    String team(String? label) {
      final normalized = label?.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '') ?? '';
      if (normalized == 'teama' || normalized == 'team1' || normalized == 'a') return widget.match.teamName('A', scorecard: widget.scorecard);
      if (normalized == 'teamb' || normalized == 'team2' || normalized == 'b') return widget.match.teamName('B', scorecard: widget.scorecard);
      if (normalized == 'id' || normalized == 'team' || normalized == 'probability') return '';
      return label?.trim().isNotEmpty == true ? label!.trim() : '';
    }
    void addProbability(Object? node, String? context, [String? hint]) {
      if (node is List) {
        for (var i = 0; i < node.length; i++) {
          addProbability(node[i], context, hint ?? (i == 0 ? 'A' : i == 1 ? 'B' : null));
        }
        return;
      }
      if (node is Map) {
        final localTeam = teamLabel(node['team_name'] ?? node['teamName'] ?? node['short_name'] ?? node['team']) ??
            teamLabel(node['name']) ?? context;
        final p = number(node['probability'] ?? node['win_probability']);
        if (p != null && p >= 0 && p <= 100) {
          final name = team(localTeam ?? hint);
          if (name.isNotEmpty) found.add(MapEntry(name, p <= 1 ? p * 100 : p));
        }
        for (final entry in node.entries) {
          final key = entry.key.toString().toLowerCase();
          if (!{'probability', 'win_probability', 'id', 'team_id', 'teamid'}.contains(key)) {
            addProbability(entry.value, localTeam, entry.key.toString());
          }
        }
      } else if (node != null) {
        final p = number(node);
        final name = team(context ?? hint);
        if (p != null && p >= 0 && p <= 100 && name.isNotEmpty) found.add(MapEntry(name, p <= 1 ? p * 100 : p));
      }
    }
    void find(Object? node, [String? context]) {
      if (node is List) {
        for (final child in node) { find(child, context); }
      } else if (node is Map) {
        final localTeam = teamLabel(node['team']) ?? teamLabel(node['team_name'] ?? node['teamName']) ?? context;
        for (final entry in node.entries) {
          if (entry.key.toString().toLowerCase() == 'win_probability') {
            addProbability(entry.value, localTeam);
          } else if (entry.value is Map || entry.value is List) {
            find(entry.value, localTeam);
          }
        }
      }
    }
    find(input);
    return found;
  }

  @override
  Widget build(BuildContext context) => _LiveMatchCardView(match: widget.match, live: widget.live, onTap: widget.onTap, scorecard: widget.scorecard, momentum: _momentum ?? (_loading ? 'Loading win probability…' : 'Win probability is currently unavailable.'));
}

class _LiveMatchCardView extends StatelessWidget {
  const _LiveMatchCardView({required this.match, required this.live, required this.onTap, required this.momentum, this.scorecard});
  final MatchData match;
  final bool live;
  final VoidCallback onTap;
  final String momentum;
  final Map<String, dynamic>? scorecard;
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFF090909), border: Border.all(color: AppColors.acid)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.circle, size: 8, color: live ? AppColors.red : AppColors.muted),
                const SizedBox(width: 6),
                Text(live ? 'LIVE' : match.status.toUpperCase(), style: const TextStyle(color: AppColors.red, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(width: 12),
                Expanded(child: Text(match.matchFormatLabel(scorecard), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.acid, fontSize: 11, fontWeight: FontWeight.bold))),
              ]),
              const Divider(color: AppColors.border),
              Row(children: [Expanded(child: _team(match, 'A')), const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('VS', style: TextStyle(color: AppColors.muted))), Expanded(child: _team(match, 'B'))]),
              const SizedBox(height: 30),
              Container(width: double.infinity, padding: const EdgeInsets.all(10), color: AppColors.surface, child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Container(width: 3, height: 54, color: AppColors.acid), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('[Momentum Shift]', style: TextStyle(color: AppColors.acid, fontSize: 12, fontWeight: FontWeight.w600)), const SizedBox(height: 8), Text(momentum, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12))])), const SizedBox(width: 8), const Icon(Icons.query_stats, color: AppColors.acid, size: 30)])),
              const SizedBox(height: 10),
              const Center(child: Text('View Full Prediction →', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
            ]),
          ),
        ),
      );
  Widget _team(MatchData match, String side) {
    final isRight = side == 'B';
    final logo = match.teamFlag(side, scorecard: scorecard);
    final badge = logo != null && logo.isNotEmpty
        ? ClipOval(child: Image.network(logo, width: 32, height: 32, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()))
        : const SizedBox(width: 23, height: 32);
    final score = match.teamScore(side, scorecard: scorecard);
    return Column(crossAxisAlignment: isRight ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: isRight ? MainAxisAlignment.end : MainAxisAlignment.start, children: [
        if (!isRight) ...[badge, const SizedBox(width: 5)],
        Flexible(child: Text(match.teamName(side, scorecard: scorecard), textAlign: isRight ? TextAlign.right : TextAlign.left, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w500))),
        if (isRight) ...[const SizedBox(width: 5), badge],
      ]),
      const SizedBox(height: 3),
      if (score == 'Yet to bat')
        Text(score, textAlign: isRight ? TextAlign.right : TextAlign.left, style: const TextStyle(color: Colors.white, fontSize: 16))
      else
        Text.rich(
          TextSpan(children: [
            TextSpan(text: score, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            if (match.teamOvers(side, scorecard: scorecard).isNotEmpty)
              TextSpan(text: ' (${match.teamOvers(side, scorecard: scorecard)} ov)', style: const TextStyle(color: Colors.white, fontSize: 12)),
          ]),
          textAlign: isRight ? TextAlign.right : TextAlign.left,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
    ]);
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({required this.match, required this.live, required this.showPrediction, required this.onTap}) : scorecard = null;
  final MatchData match;
  final bool live;
  final bool showPrediction;
  final Map<String, dynamic>? scorecard;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: live ? AppColors.acid : AppColors.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (live) const Icon(Icons.circle, size: 8, color: AppColors.red),
              if (live) const SizedBox(width: 6),
              Expanded(child: Text(match.status.toUpperCase(), style: const TextStyle(color: AppColors.acid, fontSize: 11, fontWeight: FontWeight.bold))),
              if (match.venue.isNotEmpty) Flexible(child: Text(match.venue, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 10))),
            ]),
            const Divider(color: AppColors.border, height: 22),
            Text(match.matchFormatLabel(scorecard), style: const TextStyle(color: AppColors.muted, fontSize: 10, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _team(match, 'A')),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('vs', style: TextStyle(color: AppColors.muted))),
              Expanded(child: _team(match, 'B')),
            ]),
            if (match.score.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(match.score, style: const TextStyle(color: AppColors.muted))),
            const SizedBox(height: 12),
            Row(children: [
              if (showPrediction)
                const Spacer(),
              if (showPrediction)
                TextButton(
                  onPressed: onTap,
                  style: TextButton.styleFrom(backgroundColor: AppColors.acid, foregroundColor: AppColors.background, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), shape: const RoundedRectangleBorder(), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  child: const Text('Prediction  ›', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                )
              else ...[
                const Icon(Icons.insights, color: AppColors.acid, size: 18),
                const SizedBox(width: 7),
                const Expanded(child: Text('Match overview', style: TextStyle(color: AppColors.acid, fontSize: 12))),
                const Icon(Icons.chevron_right, color: AppColors.muted, size: 18),
              ],
            ]),
          ]),
        ),
      );

  Widget _team(MatchData match, String side) {
    final logo = match.teamFlag(side, scorecard: scorecard);
    if (side == 'B') {
      return Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        Expanded(child: Text(match.teamName(side, scorecard: scorecard), textAlign: TextAlign.right, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold))),
        const SizedBox(width: 5),
        if (logo != null && logo.isNotEmpty)
          ClipOval(child: Image.network(logo, width: 24, height: 24, fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.shield, size: 24, color: AppColors.muted)))
        else
          const Icon(Icons.shield, size: 24, color: AppColors.muted),
      ]);
    }
    return Row(children: [
      if (logo != null && logo.isNotEmpty)
        ClipOval(child: Image.network(logo, width: 24, height: 24, fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.shield, size: 24, color: AppColors.muted)))
      else
        const Icon(Icons.shield, size: 24, color: AppColors.muted),
      const SizedBox(width: 5),
      Expanded(child: Text(match.teamName(side, scorecard: scorecard), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold))),
    ]);
  }
}

class MatchDetailPage extends StatefulWidget {
  const MatchDetailPage({super.key, required this.match, this.matchesFuture, this.scorecard});
  final MatchData match;
  final Future<List<MatchData>>? matchesFuture;
  final Map<String, dynamic>? scorecard;

  @override
  State<MatchDetailPage> createState() => _MatchDetailPageState();
}

class _MatchDetailPageState extends State<MatchDetailPage> {
  static const _tabs = ['Pre-match', 'Ask AI', 'Squads', 'Stats', 'Scorecard', 'Overs', 'Commentary'];
  static const _entitySportToken = 'ad51db9391daf53d64be4c4754b762d4';
  static const _prompts = ['Top Runs?', 'Top Performer?', 'Match Winner?'];
  final _question = TextEditingController();
  late Future<bool> _isLoggedIn = _checkLogin();
  final List<({String question, String answer})> _aiMessages = [];
  final Set<int> _expandedAiAnswers = {};
  final GlobalKey _latestAiContentKey = GlobalKey();
  String? _pendingAiQuestion;
  String _conversationId = '';
  bool _chatSending = false;
  int _selectedTab = 0;
  int _statsSubtab = 0;
  int _teamRunMatches = 5;
  int _teamWicketMatches = 5;
  int _teamRunPhase = 0;
  int _teamWicketPhase = 0;
  int _teamBoundaryMode = 0;
  Future<Object?>? _teamAnalysis;
  int _squadFilter = 0;
  int _batterSubtab = 0;
  int _batterMetric = 0;
  int _batterThreshold = 0;
  int _comparisonMetric = 0;
  String? _selectedBatsmanId;
  int _bowlerMetric = 0;
  int _bowlerThreshold = 0;
  String? _selectedBowlerId;
  bool _bowlerDefaultApplied = false;
  bool _squadAnnounced = false;
  int _bowlerComparisonMetric = 0;
  Future<List<Map<String, dynamic>>> _topBatters = Future.value(const []);
  Future<Object?> _batterComparison = Future.value(null);
  Future<List<Map<String, dynamic>>> _topBowlers = Future.value(const []);
  Future<Object?> _bowlerComparison = Future.value(null);
  late final Future<List<Map<String, dynamic>>> _players = _loadPlayers();
  late final Future<Object?> _preMatchReport = _loadMatchReport();
  late final Future<Object?> _groundWinningPercentage = _loadGroundData('/match-ground-analysis/winning-percentage');
  late final Future<Object?> _groundRunsByPhase = _loadGroundData('/match-ground-analysis/run-scored-in-phase');
  late final Future<Object?> _groundEconomyByPhase = _loadGroundData('/match-ground-analysis/economy-in-phase');
  late final Future<Object?> _groundBoundaries = _loadGroundData('/match-ground-analysis/boundaries-per-game');
  late final Future<Object?> _groundParScore = _loadGroundData('/match-ground-analysis/par-score');
  late final Future<Object?> _groundWickets = _loadGroundData('/match-ground-analysis/wickets-per-innings');
  late final Future<Map<String, dynamic>?> _matchScorecard = _loadDetailScorecard();
  late final Future<List<(MatchData, Map<String, dynamic>?)>> _switcherRows = _loadSwitcherRows();
  int _scorecardInnings = 0;
  int _commentaryInnings = 0;
  late final List<Future<Map<String, dynamic>?>> _commentaryInningsData = [
    _loadCommentaryInnings(1),
    _loadCommentaryInnings(2),
  ];

  Future<Map<String, dynamic>?> _loadCommentaryInnings(int innings) async {
    final matchId = widget.match.matchId.trim();
    if (matchId.isEmpty) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final uri = Uri.https('restapi.entitysport.com', '/v2/matches/$matchId/innings/$innings/commentary', {'token': _entitySportToken});
      final response = await (await client.getUrl(uri)).close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) throw HttpException('Commentary returned ${response.statusCode}');
      final decoded = jsonDecode(body);
      if (decoded is! Map || decoded['response'] is! Map) throw const FormatException('Invalid commentary response');
      return Map<String, dynamic>.from(decoded['response'] as Map);
    } finally { client.close(force: true); }
  }

  @override
  void initState() {
    super.initState();
    _teamAnalysis = _loadTeamAnalysis();
  }

  Future<bool> _checkLogin() async {
    final token = await AuthService.instance.accessToken();
    return token != null && token.isNotEmpty;
  }

  Future<bool> _requireLogin() async {
    if (await _checkLogin()) return true;
    if (!mounted) return false;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => LoginPage(onLoggedIn: () {
      if (mounted) setState(() => _isLoggedIn = Future.value(true));
    })));
    final loggedIn = await _checkLogin();
    if (mounted) setState(() => _isLoggedIn = Future.value(loggedIn));
    return loggedIn;
  }

  Future<bool> _ensureMatchUnlocked() async {
    final matchId = widget.match.matchId.trim();
    if (matchId.isEmpty) throw const AuthException('This match is missing its match ID.');
    if ((await AuthService.instance.unlockedMatches()).contains(matchId)) return true;

    final passes = await AuthService.instance.remainingPasses();
    var eligible = false;
    if (passes <= 0) eligible = await AuthService.instance.freeTrialEligible();
    if (!mounted) return false;

    final action = await showDialog<String>(context: context, builder: (dialogContext) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Unlock this match'),
      content: Text(passes > 0
          ? 'Use 1 pass to chat with Spoda AI about this match.'
          : eligible ? 'Activate your free trial to chat with Spoda AI about this match.' : 'You need a pass to chat with Spoda AI about this match.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(dialogContext, passes > 0 ? 'pass' : eligible ? 'trial' : 'buy'), child: Text(passes > 0 ? 'Unlock match with 1 pass' : eligible ? 'Activate free trial' : 'Buy More Passes', style: const TextStyle(color: AppColors.acid))),
      ],
    ));
    if (!mounted || action == null) return false;
    if (action == 'buy') {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MatchPassesPage()));
      return false;
    }
    if (action == 'pass') {
      await AuthService.instance.usePass(matchId);
    } else {
      await AuthService.instance.activateFreeTrial(matchId);
    }
    return true;
  }

  Future<void> _submitAiQuestion({bool openAiTab = false}) async {
    final question = _question.text.trim();
    if (question.isEmpty || _chatSending) return;
    try {
      if (!await _requireLogin()) return;
      if (!await _ensureMatchUnlocked()) return;
      if (!mounted) return;
      setState(() {
        _chatSending = true;
        _pendingAiQuestion = question;
        _question.clear();
        _selectedTab = 1;
      });
      _scrollLatestAiContentIntoView();
      final response = await AuthService.instance.sendAgentMessage(
        collectionId: widget.match.matchId.trim(),
        question: question,
        conversationId: _conversationId,
        isLive: widget.match.status.toLowerCase().contains('live') || widget.match.status.toLowerCase().contains('in progress'),
      );
      if (!mounted) return;
      final answer = (response['widgets'] ?? response['answer'] ?? '').toString();
      final nextConversation = response['conversationId']?.toString() ?? '';
      setState(() {
        _aiMessages.add((question: question, answer: answer));
        if (nextConversation.isNotEmpty) _conversationId = nextConversation;
        _pendingAiQuestion = null;
        _selectedTab = 1;
      });
      _scrollLatestAiContentIntoView();
    } on AuthException catch (error) {
      if (mounted) {
        setState(() { _pendingAiQuestion = null; _question.text = question; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (error) {
      if (mounted) {
        setState(() { _pendingAiQuestion = null; _question.text = question; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not send your question: $error')));
      }
    } finally {
      if (mounted) setState(() => _chatSending = false);
    }
  }

  Future<Map<String, dynamic>?> _loadDetailScorecard() async {
    if (widget.match.matchId.isEmpty) return widget.scorecard;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final uri = Uri.https('api.spoda.ai', '/match-scorecard', {'matchId': widget.match.matchId});
      final response = await (await client.getUrl(uri)).close();
      if (response.statusCode < 200 || response.statusCode >= 300) return widget.scorecard;
      final payload = jsonDecode(await response.transform(utf8.decoder).join());
      return payload is Map ? Map<String, dynamic>.from(payload) : widget.scorecard;
    } catch (_) { return widget.scorecard; } finally { client.close(force: true); }
  }

  String? _teamId(String side) {
    final rawTeam = widget.match.raw['team$side'];
    if (rawTeam is Map) {
      for (final key in ['teamId', 'team_id', 'id', 'teamid']) {
        final value = rawTeam[key];
        if (value != null && value.toString().isNotEmpty) return value.toString();
      }
    }
    final candidates = side == 'A'
        ? ['teamOneId', 'team_one_id', 'team1Id', 'team1_id', 'teamId1', 'team_id1', 'teamAId', 'team_a_id']
        : ['teamTwoId', 'team_two_id', 'team2Id', 'team2_id', 'teamId2', 'team_id2', 'teamBId', 'team_b_id'];
    for (final key in candidates) {
      final value = widget.match.raw[key];
      if (value != null && value.toString().isNotEmpty) return value.toString();
    }
    return null;
  }

  Future<Object?> _loadTeamAnalysis() async {
    final one = _teamId('A'), two = _teamId('B');
    if (widget.match.matchId.isEmpty || one == null || two == null) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final uri = Uri.https('api.spoda.ai', '/match-team-analysis/team', {
        'matchId': widget.match.matchId,
        'teamOneId': one,
        'teamTwoId': two,
      });
      
      final response = await (await client.getUrl(uri)).close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) throw HttpException('Team analysis returned ${response.statusCode}');
      return jsonDecode(body);
    } finally { client.close(force: true); }
  }

  String? _groundId() {
    Object? find(Object? value) {
      if (value is Map) {
        for (final entry in value.entries) {
          final key = entry.key.toString().toLowerCase().replaceAll(RegExp(r'[_-]'), '');
          if (key == 'groundid' || key == 'venueid' || key == 'stadiumid') return entry.value;
        }
        for (final entry in value.values) { final result = find(entry); if (result != null) return result; }
      } else if (value is List) {
        for (final item in value) { final result = find(item); if (result != null) return result; }
      }
      return null;
    }
    return find(widget.match.raw)?.toString();
  }

  Future<Object?> _loadGroundData(String path) async {
    final groundId = _groundId();
    if (widget.match.matchId.isEmpty || groundId == null || groundId.isEmpty) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final uri = Uri.https('api.spoda.ai', path, {
        'matchId': widget.match.matchId,
        'groundId': groundId,
      });
      final response = await (await client.getUrl(uri)).close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) throw HttpException('Ground analysis returned ${response.statusCode}');
      return jsonDecode(body);
    } finally { client.close(force: true); }
  }

  Future<Object?> _loadMatchReport() async {
    if (widget.match.matchId.isEmpty) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final uri = Uri.https('spoda.ai', '/api/match-report', {'matchId': widget.match.matchId});
      final response = await (await client.getUrl(uri)).close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) throw HttpException('Match report returned ${response.statusCode}');
      return jsonDecode(body);
    } finally { client.close(force: true); }
  }

  static const _batterMetrics = ['Run Scored', 'Strike Rate', 'Balls Faced'];
  static const _comparisonMetrics = ['Dismissal', 'Strike rate'];
  static const _bowlerMetrics = ['Wicket Taken', 'Economy Rate', 'Boundaries'];
  static const _bowlerComparisonMetrics = ['Dismissal', 'Strike rate'];
  List<String> get _bowlerThresholds => switch (_bowlerMetric) {
    0 => ['1 or more', '2 or more', '3 or more'],
    1 => ['Up to 6', 'Up to 7', 'Up to 8'],
    _ => ['Up to 4', 'Up to 10'],
  };

  void _selectBowlerMetric(int? value) {
    if (value == null) return;
    setState(() { _bowlerMetric = value; _bowlerThreshold = 0; _loadTopBowlers(); });
  }

  void _selectBowlerThreshold(int? value) {
    if (value == null) return;
    setState(() { _bowlerThreshold = value; _loadTopBowlers(); });
  }

  void _loadTopBowlers() {
    final threshold = int.parse(_bowlerThresholds[_bowlerThreshold].split(' ')[_bowlerMetric == 0 ? 0 : 2]);
    final (path, parameter) = switch (_bowlerMetric) {
      0 => ('/top-bowler/wickets', 'minWicketsTaken'),
      1 => ('/top-bowler/economy', 'maxEconomyRate'),
      _ => ('/top-bowler/boundaries', 'maxBoundaries'),
    };
    _topBowlers = _fetchTopBatters(path, parameter, threshold);
  }

  void _selectBowler(String? playerId) {
    setState(() { _bowlerDefaultApplied = true; _selectedBowlerId = playerId; _loadBowlerComparison(); });
  }

  void _selectBowlerComparisonMetric(int? metric) {
    if (metric == null) return;
    setState(() { _bowlerComparisonMetric = metric; _loadBowlerComparison(); });
  }

  void _loadBowlerComparison() {
    final path = _bowlerComparisonMetric == 0
        ? '/top-bowler/compare/dismissal-rate'
        : '/top-bowler/compare/strike-rate';
    _bowlerComparison = _fetchBowlerComparison(path, _selectedBowlerId ?? '');
  }

  Future<Object?> _fetchBowlerComparison(String path, String bowlerId) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final uri = Uri.https('api.spoda.ai', path, {'matchId': widget.match.matchId, 'bowlerId': bowlerId});
      final response = await (await client.getUrl(uri)).close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) throw HttpException('Bowler comparison returned ${response.statusCode}');
      final decoded = jsonDecode(body);
      return decoded is Map ? (decoded['data'] ?? decoded['results'] ?? decoded) : decoded;
    } finally { client.close(force: true); }
  }
  List<String> get _batterThresholds => switch (_batterMetric) {
    0 => ['20 or more', '50 or more', '100 or more'],
    1 => ['50 or more', '100 or more'],
    _ => ['10 or more', '20 or more', '50 or more'],
  };

  void _selectBatterMetric(int? value) {
    if (value == null) return;
    setState(() {
      _batterMetric = value;
      _batterThreshold = 0;
      _loadTopBatters();
    });
  }

  void _selectBatterThreshold(int? value) {
    if (value == null) return;
    setState(() {
      _batterThreshold = value;
      _loadTopBatters();
    });
  }

  void _loadTopBatters() {
    final metric = _batterMetric;
    final threshold = int.parse(_batterThresholds[_batterThreshold].split(' ').first);
    final (path, parameter) = switch (metric) {
      0 => ('/top-bastman/runs-scored', 'minRunsScored'),
      1 => ('/top-bastman/strike-rate', 'minStrikeRate'),
      _ => ('/top-bastman/balls-faced', 'minBallsFaced'),
    };
    _topBatters = _fetchTopBatters(path, parameter, threshold);
  }

  Future<List<Map<String, dynamic>>> _fetchTopBatters(String path, String parameter, int threshold) async {
    if (widget.match.matchId.isEmpty) return [];
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final uri = Uri.https('api.spoda.ai', path, {'matchId': widget.match.matchId, parameter: '$threshold'});
      final response = await (await client.getUrl(uri)).close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) throw HttpException('Top batter returned ${response.statusCode}');
      final decoded = jsonDecode(body);
      return _decodePlayers(decoded is Map ? (decoded['data'] ?? decoded['results'] ?? decoded['players'] ?? decoded) : decoded);
    } finally { client.close(force: true); }
  }

  void _selectComparisonPlayer(String? playerId) {
    setState(() {
      _selectedBatsmanId = playerId;
      _loadBatterComparison();
    });
  }

  void _selectComparisonMetric(int? metric) {
    if (metric == null) return;
    setState(() {
      _comparisonMetric = metric;
      _loadBatterComparison();
    });
  }

  void _loadBatterComparison() {
    final playerId = _selectedBatsmanId;
    if (playerId == null) {
      _batterComparison = Future.value(null);
      return;
    }
    final path = _comparisonMetric == 0
        ? '/top-bastman/compare/dismissal-rate'
        : '/top-bastman/compare/strike-rate';
    _batterComparison = _fetchBatterComparison(path, playerId);
  }

  Future<Object?> _fetchBatterComparison(String path, String playerId) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final uri = Uri.https('api.spoda.ai', path, {'matchId': widget.match.matchId, 'batsmanId': playerId});
      final response = await (await client.getUrl(uri)).close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) throw HttpException('Batter comparison returned ${response.statusCode}');
      final decoded = jsonDecode(body);
      return decoded is Map ? (decoded['data'] ?? decoded['results'] ?? decoded) : decoded;
    } finally { client.close(force: true); }
  }

  Future<List<Map<String, dynamic>>> _loadPlayers() async {
    if (widget.match.matchId.isEmpty) return [];
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final uri = Uri.https('api.spoda.ai', '/match-player-analysis/players', {'matchId': widget.match.matchId});
      final response = await (await client.getUrl(uri)).close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) throw HttpException('Players returned ${response.statusCode}');
      final payload = jsonDecode(body);
      final announced = _readSquadAnnounced(payload);
      if (announced != null && mounted) {
        setState(() => _squadAnnounced = announced);
      }
      return _decodePlayers(payload);
    } finally { client.close(force: true); }
  }

  bool? _readSquadAnnounced(Object? value) {
    if (value is List) {
      for (final item in value) {
        final result = _readSquadAnnounced(item);
        if (result != null) return result;
      }
    } else if (value is Map) {
      for (final entry in value.entries) {
        final key = entry.key.toString().toLowerCase().replaceAll(RegExp(r'[_-]'), '');
        if (key == 'squadannounced') {
          final raw = entry.value;
          if (raw is bool) return raw;
          if (raw is String) {
            if (raw.toLowerCase() == 'true') return true;
            if (raw.toLowerCase() == 'false') return false;
          }
          if (raw is num) return raw != 0;
        }
      }
      for (final nested in value.values) {
        final result = _readSquadAnnounced(nested);
        if (result != null) return result;
      }
    }
    return null;
  }

  List<Map<String, dynamic>> _decodePlayers(Object? value, [String? inheritedTeam]) {
    final rows = <Map<String, dynamic>>[];
    if (value is List) {
      for (final item in value) { rows.addAll(_decodePlayers(item, inheritedTeam)); }
    } else if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      final team = (map['teamName'] ?? map['team_name'] ?? map['team'] ?? map['name'] ?? inheritedTeam)?.toString();
      final nested = map['players'] ?? map['squad'] ?? map['playerList'] ?? map['player_list'] ?? map['data'] ?? map['results'];
      if (nested is List) {
        rows.addAll(_decodePlayers(nested, team));
      } else if (map['player'] is Map) {
        rows.addAll(_decodePlayers(map['player'], team));
      } else if (map['playerName'] != null || map['player_name'] != null || map['fullName'] != null || map['name'] != null) {
        rows.add({...map, '_teamLabel': ?inheritedTeam});
      } else {
        for (final entry in map.entries) {
          if (entry.value is List || entry.value is Map) rows.addAll(_decodePlayers(entry.value, entry.key.toString()));
        }
      }
    }
    return rows;
  }

  @override
  void dispose() { _question.dispose(); super.dispose(); }

  bool _switcherIsLive(MatchData match) => match.group == 'live' || '${match.status} ${match.raw}'.toLowerCase().contains(RegExp(r'live|in.?progress|innings|stumps'));
  bool _switcherIsDone(MatchData match) => match.group == 'previous' || '${match.status} ${match.raw}'.toLowerCase().contains(RegExp(r'complete|finished|result|won|abandoned'));
  String _switcherTitle(MatchData match, [Map<String, dynamic>? scorecard]) {
    final teamA = match.teamName('A', scorecard: scorecard);
    final teamB = match.teamName('B', scorecard: scorecard);
    if (!teamA.toLowerCase().startsWith('team ') && !teamB.toLowerCase().startsWith('team ')) return '$teamA VS $teamB';
    return match.title.replaceAll(RegExp(r'\s+vs\s+', caseSensitive: false), ' VS ');
  }

  Future<List<(MatchData, Map<String, dynamic>?)>> _loadSwitcherRows() async {
    final allMatches = await (widget.matchesFuture ?? Future.value([widget.match]));
    final matches = allMatches.where((match) => _switcherIsLive(match) || (!_switcherIsDone(match) && (match.startDate == null || match.startDate!.isAfter(DateTime.now())))).toList();
    if (!matches.any((match) => match.matchId == widget.match.matchId)) matches.add(widget.match);
    final scorecards = await Future.wait(matches.map(_loadSwitcherScorecard));
    return List.generate(matches.length, (index) => (matches[index], scorecards[index]));
  }

  Future<Map<String, dynamic>?> _loadSwitcherScorecard(MatchData match) async {
    if (match.matchId == widget.match.matchId) return widget.scorecard ?? await _matchScorecard;
    if (match.matchId.isEmpty) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final uri = Uri.https('api.spoda.ai', '/match-scorecard', {'matchId': match.matchId});
      final response = await (await client.getUrl(uri)).close();
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final payload = jsonDecode(await response.transform(utf8.decoder).join());
      return payload is Map ? Map<String, dynamic>.from(payload) : null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Widget _matchTitleMenu() => FutureBuilder<List<(MatchData, Map<String, dynamic>?)>>(
    future: _switcherRows,
    builder: (context, snapshot) {
      final rows = snapshot.data ?? const <(MatchData, Map<String, dynamic>?)>[];
      final live = rows.where((row) => _switcherIsLive(row.$1)).toList();
      final upcoming = rows.where((row) => !_switcherIsLive(row.$1) && !_switcherIsDone(row.$1) && (row.$1.startDate == null || row.$1.startDate!.isAfter(DateTime.now()))).toList();
      final currentRows = rows.where((row) => row.$1.matchId == widget.match.matchId);
      final current = currentRows.isEmpty ? null : currentRows.first;
      return PopupMenuButton<MatchData?>(
        tooltip: 'Switch match',
        onSelected: (match) {
          if (match == null || match.matchId == widget.match.matchId) return;
          Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => MatchDetailPage(match: match, matchesFuture: widget.matchesFuture)));
        },
        itemBuilder: (context) => [
          if (live.isNotEmpty) ...[
            const PopupMenuItem<MatchData?>(enabled: false, child: Text('LIVE MATCHES', style: TextStyle(color: AppColors.acid, fontSize: 11, fontWeight: FontWeight.w700))),
            ...live.map((row) => PopupMenuItem<MatchData?>(value: row.$1, child: Text(_switcherTitle(row.$1, row.$2), maxLines: 1, overflow: TextOverflow.ellipsis))),
          ],
          if (upcoming.isNotEmpty) ...[
            const PopupMenuItem<MatchData?>(enabled: false, child: Text('UPCOMING MATCHES', style: TextStyle(color: AppColors.acid, fontSize: 11, fontWeight: FontWeight.w700))),
            ...upcoming.map((row) => PopupMenuItem<MatchData?>(value: row.$1, child: Text(_switcherTitle(row.$1, row.$2), maxLines: 1, overflow: TextOverflow.ellipsis))),
          ],
          if (live.isEmpty && upcoming.isEmpty)
            const PopupMenuItem<MatchData?>(enabled: false, child: Text('No other live or upcoming matches')),
        ],
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(child: Text(_switcherTitle(widget.match, current?.$2 ?? widget.scorecard), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14))),
          const SizedBox(width: 4),
          const Icon(Icons.arrow_drop_down, size: 20),
        ]),
      );
    },
  );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.background,
          titleSpacing: 0,
          title: _matchTitleMenu(),
        ),
        body: SafeArea(child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 12), child: FutureBuilder<Map<String, dynamic>?>(
            future: _matchScorecard,
            builder: (context, snapshot) {
              final scorecard = snapshot.data ?? widget.scorecard;
              final startDate = widget.match.startDate;
              final startingSoon = startDate != null && startDate.isAfter(DateTime.now());
              return Row(children: [
                Expanded(child: _detailTeam(widget.match, 'A', scorecard: scorecard)),
                Column(children: [
                  Text(startingSoon ? 'Starting in' : widget.match.status, style: const TextStyle(color: Color(0xFFFF8D45), fontSize: 16)),
                  const SizedBox(height: 3),
                  Text(startingSoon ? _detailCountdown(startDate!) : startDate == null ? 'Match details' : _detailTime(startDate), style: const TextStyle(color: Color(0xFFFF8D45), fontSize: 16)),
                ]),
                Expanded(child: _detailTeam(widget.match, 'B', rightAlign: true, scorecard: scorecard)),
              ]);
            },
          )),
          Container(
            height: 48,
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFF404040)), bottom: BorderSide(color: Color(0xFF404040)))),
            child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _tabs.length,
            itemBuilder: (context, i) {
              final label = i == 2 && _squadAnnounced ? 'Playing XI' : _tabs[i];
              return InkWell(
                onTap: () => setState(() => _selectedTab = i),
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _selectedTab == i ? const Color(0xFFE7FF00) : Colors.transparent, width: 2))),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Center(child: Text(label, maxLines: 1, style: TextStyle(fontSize: 16, color: _selectedTab == i ? const Color(0xFFF1F1F1) : const Color(0xFFA8A8A8), fontWeight: FontWeight.w600))),
                ),
              );
            },
          )),
          Expanded(child: switch (_selectedTab) {
            0 => _preMatchReportContent(),
            2 => _squadsContent(),
            3 => _groundStatsContent(),
            4 => _scorecardContent(),
            5 => _oversContent(),
            6 => _commentaryContent(),
            1 => _askAiTab(),
            _ => const SizedBox.expand(),
          }),
        ])),
      );

  Map<String, dynamic>? _commentaryInning(Map<String, dynamic>? response) => response?['inning'] is Map
      ? Map<String, dynamic>.from(response!['inning'] as Map)
      : null;

  List<Map<String, dynamic>> _commentaryRows(Map<String, dynamic>? response) {
    if (response == null) return const [];
    for (final key in ['commentaries', 'commentary', 'balls', 'ball_by_ball']) {
      final value = response[key];
      if (value is List) return value.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList();
      if (value is Map) {
        for (final nestedKey in ['items', 'data', 'commentaries', 'rows']) {
          final nested = value[nestedKey];
          if (nested is List) return nested.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList();
        }
      }
    }
    return const [];
  }

  String _inningsTeamName(Map<String, dynamic>? response, int index) {
    final inning = _commentaryInning(response);
    final full = (inning?['name'] ?? '').toString().replaceFirst(RegExp(r'\s+Inning$', caseSensitive: false), '').trim();
    if (full.isNotEmpty) return full;
    return widget.match.teamName(index == 0 ? 'A' : 'B', scorecard: widget.scorecard);
  }

  String? _inningsTeamLogo(Map<String, dynamic>? response, int index) {
    final inning = _commentaryInning(response);
    final teamId = inning?['batting_team_id']?.toString();
    String? findLogo(Object? node) {
      if (node is Map) {
        if (teamId != null && node[teamId] is Map) {
          final keyed = node[teamId] as Map;
          final logo = keyed['logo_url'] ?? keyed['thumb_url'] ?? keyed['logo'];
          if (logo is String && logo.isNotEmpty) return logo;
        }
        final id = (node['tid'] ?? node['team_id'] ?? node['teamId'] ?? node['id'])?.toString();
        if (teamId != null && id == teamId) {
          final logo = node['logo_url'] ?? node['thumb_url'] ?? node['logo'];
          if (logo is String && logo.isNotEmpty) return logo;
        }
        for (final value in node.values) {
          final found = findLogo(value);
          if (found != null) return found;
        }
      } else if (node is List) {
        for (final value in node) {
          final found = findLogo(value);
          if (found != null) return found;
        }
      }
      return null;
    }
    return findLogo(response?['teams']) ?? widget.match.teamFlag(index == 0 ? 'A' : 'B', scorecard: widget.scorecard);
  }

  Widget _inningsTeamHeading(Map<String, dynamic>? response, int index, {bool selected = false, VoidCallback? onTap}) {
    final logo = _inningsTeamLogo(response, index);
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(color: selected ? const Color(0xFF292929) : AppColors.surface, border: Border.all(color: selected ? AppColors.acid : AppColors.border)),
        child: Row(children: [
          if (logo != null && logo.startsWith('http')) ...[
            Image.network(logo, width: 20, height: 20, errorBuilder: (_, _, _) => const Icon(Icons.shield_outlined, size: 18, color: AppColors.muted)),
            const SizedBox(width: 6),
          ],
          Expanded(child: Text(_inningsTeamName(response, index), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
        ]),
      ),
    );
  }

  Widget _oversContent() => FutureBuilder<List<Map<String, dynamic>?>>(
    future: Future.wait(_commentaryInningsData),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) return _askAiStatus('', loading: true);
      if (snapshot.hasError || snapshot.data == null) return _askAiStatus('Overs are not available right now.');
      final responses = snapshot.data!;
      final overMaps = [_oversForInning(responses[0]), _oversForInning(responses[1])];
      final overKeys = <String>{...overMaps[0].keys, ...overMaps[1].keys}.toList()
        ..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
      return Column(children: [
        Row(children: [
          const SizedBox(width: 44, child: Center(child: Text('Ovs', style: TextStyle(color: AppColors.muted, fontSize: 10, fontWeight: FontWeight.w600)))),
          for (var i = 0; i < 2; i++) Expanded(child: _inningsTeamHeading(responses[i], i)),
        ]),
        Expanded(child: ListView.builder(
          itemCount: (overKeys.isEmpty ? 1 : overKeys.length) + 1,
          itemBuilder: (context, index) {
            if (index == (overKeys.isEmpty ? 1 : overKeys.length)) return _askAiSection();
            if (overKeys.isEmpty) return const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('No overs yet', style: TextStyle(color: AppColors.muted, fontSize: 11))));
            final over = overKeys[index];
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 44, child: Center(child: Text('${(int.tryParse(over) ?? 0) + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)))),
              for (var i = 0; i < 2; i++) Expanded(child: _oversInningsCell(overMaps[i][over])),
            ]);
          },
        )),
      ]);
    },
  );

  Widget _oversInningsColumn(Map<String, dynamic>? response) {
    final inning = _commentaryInning(response);
    final balls = _commentaryRows(response).where((row) {
      final event = (row['event'] ?? 'ball').toString().toLowerCase();
      return event == 'ball' || event == 'wicket';
    }).toList();
    final byOver = <String, List<Map<String, dynamic>>>{};
    for (final row in balls) {
      byOver.putIfAbsent(row['over']?.toString() ?? '0', () => []).add(row);
    }
    final overs = byOver.keys.toList()..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
    if (overs.isEmpty) return const Padding(padding: EdgeInsets.all(14), child: Center(child: Text('No overs yet', style: TextStyle(color: AppColors.muted, fontSize: 11))));
    return Column(children: [
      if (inning != null) Container(width: double.infinity, padding: const EdgeInsets.all(8), color: const Color(0xFF202020), child: Text('${inning['scores'] ?? '—'}  (${inning['scores_full'] ?? ''})', textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700))),
      const Padding(padding: EdgeInsets.fromLTRB(9, 8, 9, 5), child: Row(children: [SizedBox(width: 34, child: Text('Ovs', style: TextStyle(color: AppColors.muted, fontSize: 10, fontWeight: FontWeight.w600))), Expanded(child: Text('Runs', style: TextStyle(color: AppColors.muted, fontSize: 10, fontWeight: FontWeight.w600)))])),
      for (final over in overs)
        Builder(builder: (_) {
          final entries = byOver[over]!;
          final runs = entries.fold<int>(0, (total, ball) => total + (int.tryParse((ball['run'] ?? ball['score'] ?? 0).toString()) ?? 0));
          final wickets = entries.where((ball) => (ball['event'] ?? '').toString() == 'wicket' || ball['wicket'] == true || ball['noball_dismissal'] == true).length;
          final overNumber = (int.tryParse(over) ?? 0) + 1;
          return Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10), decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 34, child: Text('$overNumber', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$runs/$wickets', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
            const SizedBox(height: 5),
            Wrap(spacing: 4, runSpacing: 4, children: entries.map((ball) {
              final run = (ball['run'] ?? ball['score'] ?? 0).toString();
              final isWicket = (ball['event'] ?? '').toString() == 'wicket' || ball['wicket'] == true || ball['noball_dismissal'] == true;
              final isBoundary = ball['four'] == true || ball['six'] == true;
              final color = isWicket ? AppColors.red : isBoundary ? AppColors.acid : run == '0' ? const Color(0xFF444444) : const Color(0xFF1685A2);
              return Container(width: 20, height: 20, alignment: Alignment.center, decoration: BoxDecoration(color: color, shape: BoxShape.circle), child: Text(isWicket ? 'W' : run, style: TextStyle(color: isBoundary ? Colors.black : Colors.white, fontSize: 9, fontWeight: FontWeight.w700)));
            }).toList()),
          ])),
          ]));
        }),
    ]);
  }

  Map<String, List<Map<String, dynamic>>> _oversForInning(Map<String, dynamic>? response) {
    final byOver = <String, List<Map<String, dynamic>>>{};
    var deliveryIndex = 0;
    for (final ball in _commentaryRows(response)) {
      final event = (ball['event'] ?? 'ball').toString().trim().toLowerCase();
      if (event == 'overend') continue;
      final rawOver = ball['over'] ?? ball['over_number'] ?? ball['overNumber'] ?? ball['over_no'];
      final overText = rawOver?.toString().trim() ?? '';
      final over = int.tryParse(overText) ?? int.tryParse(overText.split('.').first);
      final overKey = '${over ?? (deliveryIndex ~/ 6)}';
      byOver.putIfAbsent(overKey, () => []).add(ball);
      deliveryIndex++;
    }
    return byOver;
  }

  Widget _oversInningsCell(List<Map<String, dynamic>>? entries) {
    if (entries == null || entries.isEmpty) {
      return Container(padding: const EdgeInsets.all(10), alignment: Alignment.center, decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border), left: BorderSide(color: AppColors.border))), child: const Text('—', style: TextStyle(color: AppColors.muted, fontSize: 11)));
    }
    final runs = entries.fold<int>(0, (total, ball) => total + (int.tryParse((ball['run'] ?? ball['score'] ?? 0).toString()) ?? 0));
    final wickets = entries.where((ball) => (ball['event'] ?? '').toString() == 'wicket' || ball['wicket'] == true || ball['noball_dismissal'] == true).length;
    return Container(padding: const EdgeInsets.all(8), decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border), left: BorderSide(color: AppColors.border))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('$runs/$wickets', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
      const SizedBox(height: 5),
      Wrap(spacing: 3, runSpacing: 3, children: entries.map((ball) {
        final run = (ball['run'] ?? ball['score'] ?? 0).toString();
        final isWicket = (ball['event'] ?? '').toString() == 'wicket' || ball['wicket'] == true || ball['noball_dismissal'] == true;
        final isBoundary = ball['four'] == true || ball['six'] == true;
        final color = isWicket ? AppColors.red : isBoundary ? AppColors.acid : run == '0' ? const Color(0xFF444444) : const Color(0xFF1685A2);
        return Container(width: 18, height: 18, alignment: Alignment.center, decoration: BoxDecoration(color: color, shape: BoxShape.circle), child: Text(isWicket ? 'W' : run, style: TextStyle(color: isBoundary ? Colors.black : Colors.white, fontSize: 8, fontWeight: FontWeight.w700)));
      }).toList()),
    ]));
  }

  Widget _commentaryContent() => FutureBuilder<List<Map<String, dynamic>?>>(
    future: Future.wait(_commentaryInningsData),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) return _askAiStatus('', loading: true);
      if (snapshot.hasError || snapshot.data == null) return _askAiStatus('Commentary is not available right now.');
      final responses = snapshot.data!;
      final rows = _commentaryRows(responses[_commentaryInnings]);
      return Column(children: [
        Row(children: [for (var i = 0; i < 2; i++) Expanded(child: _inningsTeamHeading(responses[i], i, selected: _commentaryInnings == i, onTap: () => setState(() => _commentaryInnings = i)))]),
        Expanded(child: rows.isEmpty
          ? ListView(children: [const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('No commentary available yet.', style: TextStyle(color: AppColors.muted)))), _askAiSection()])
          : ListView.builder(
              itemCount: rows.length + 1,
              itemBuilder: (context, index) {
                if (index == rows.length) return _askAiSection();
                final row = rows[rows.length - index - 1];
                final over = (int.tryParse(row['over']?.toString() ?? '') ?? -1) + 1;
                final ball = row['ball']?.toString() ?? '';
                final event = (row['event'] ?? 'ball').toString().toLowerCase();
                final isWicket = event == 'wicket' || row['wicket'] == true || row['noball_dismissal'] == true;
                final isBoundary = row['four'] == true || row['six'] == true;
                final result = isWicket ? 'W' : (row['run'] ?? row['score'] ?? '•').toString();
                final color = isWicket ? AppColors.red : isBoundary ? AppColors.acid : const Color(0xFF1685A2);
                final title = (row['commentary'] ?? row['text'] ?? '').toString().trim();
                return Container(padding: const EdgeInsets.fromLTRB(14, 12, 14, 13), decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 45, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(over < 1 ? '—' : '$over.$ball', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)), const SizedBox(height: 7), Container(width: 19, height: 19, alignment: Alignment.center, decoration: BoxDecoration(color: color, shape: BoxShape.circle), child: Text(result, style: TextStyle(fontSize: 9, color: isBoundary ? Colors.black : Colors.white, fontWeight: FontWeight.w700)))])),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title.isEmpty ? event : title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)), if (row['text'] != null && row['text'].toString().trim().isNotEmpty) ...[const SizedBox(height: 5), Text(row['text'].toString(), style: const TextStyle(color: AppColors.muted, fontSize: 11, height: 1.4))]])),
                ]));
              },
            )),
      ]);
    },
  );

  Widget _scorecardContent() => FutureBuilder<Map<String, dynamic>?>(
    future: _matchScorecard,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) return _askAiStatus('', loading: true);
      final root = snapshot.data;
      final data = root?['data'];
      final response = data is Map ? data['response'] : null;
      final inningsRaw = response is Map ? response['innings'] : null;
      if (inningsRaw is! List || inningsRaw.isEmpty) return _askAiStatus('Scorecard is not available yet.');
      final innings = inningsRaw.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList()
        ..sort((a, b) => (_scorecardNumber(a['number'])).compareTo(_scorecardNumber(b['number'])));
      final selected = _scorecardInnings.clamp(0, innings.length - 1);
      final inning = innings[selected];
      return Column(children: [
        if (innings.length > 1) SizedBox(height: 48, child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          itemCount: innings.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final active = index == selected;
            final team = _scorecardTeamName(innings[index]);
            return InkWell(onTap: () => setState(() => _scorecardInnings = index), child: Container(
              constraints: const BoxConstraints(minWidth: 120), padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center, color: active ? AppColors.acid : const Color(0xFF202020),
              child: Text('$team - ${innings[index]['scores'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: active ? Colors.black : Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
            ));
          },
        )),
        Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 16), children: [
          _scorecardSection('Batter', _scorecardRows(inning['batsmen'])),
          _scorecardInningExtras(inning),
          _scorecardYetToBat(inning),
          _scorecardFallOfWickets(inning),
          _scorecardSection('Bowler', _scorecardRows(inning['bowlers'])),
          _scorecardPartnership(inning),
          _askAiSection(),
        ])),
      ]);
    },
  );

  int _scorecardNumber(Object? value) => int.tryParse(value?.toString() ?? '') ?? 0;
  String _scorecardTeamName(Map<String, dynamic> inning) {
    final raw = (inning['name'] ?? inning['short_name'] ?? '').toString().trim();
    return raw.replaceFirst(RegExp(r'\s+Inning$', caseSensitive: false), '').trim().isEmpty
        ? widget.match.teamName(_scorecardNumber(inning['number']) <= 1 ? 'A' : 'B', scorecard: widget.scorecard)
        : raw.replaceFirst(RegExp(r'\s+Inning$', caseSensitive: false), '').trim();
  }
  List<Map<String, dynamic>> _scorecardRows(Object? value) => value is List ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : const [];
  String _scorecardValue(Map<String, dynamic> row, List<String> keys, [String fallback = '0']) {
    for (final key in keys) { final value = row[key]; if (value != null && value.toString().isNotEmpty) return value.toString(); }
    return fallback;
  }
  Widget _scorecardHeading(String title, {String? columns}) => Container(
    color: const Color(0xFF292929), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
    child: Row(children: [Expanded(child: Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))), if (columns != null) Text(columns, style: const TextStyle(fontSize: 10, color: AppColors.muted))]),
  );
  Widget _scorecardSection(String title, List<Map<String, dynamic>> rows) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    _scorecardHeading(title, columns: title == 'Batter' ? 'R     B    4s   6s    SR' : 'OV    M    R    W    ECO'),
    if (rows.isEmpty) _scorecardLine('No $title data'),
    ...rows.map((row) {
      final batting = title == 'Batter';
      final name = _scorecardValue(row, ['name', 'title'], '—');
      final stats = batting
          ? '${_scorecardValue(row, ['runs'])}    ${_scorecardValue(row, ['balls_faced', 'balls'])}    ${_scorecardValue(row, ['fours'])}    ${_scorecardValue(row, ['sixes'])}    ${_scorecardValue(row, ['strike_rate', 'sr'])}'
          : '${_scorecardValue(row, ['overs'])}    ${_scorecardValue(row, ['maidens'])}    ${_scorecardValue(row, ['runs_conceded', 'runs'])}    ${_scorecardValue(row, ['wickets'])}    ${_scorecardValue(row, ['econ', 'economy'])}';
      final howOut = (row['how_out'] ?? '').toString();
      return Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11), decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [Expanded(child: Text(name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))), Text(stats, style: const TextStyle(fontSize: 10, color: Colors.white70))]),
        if (batting && howOut.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(howOut, style: const TextStyle(fontSize: 10, color: AppColors.muted))),
      ]));
    }),
  ]);
  Widget _scorecardLine(String text) => Padding(padding: const EdgeInsets.all(10), child: Text(text, style: const TextStyle(fontSize: 11, color: AppColors.muted)));
  Widget _scorecardInningExtras(Map<String, dynamic> inning) {
    final extras = inning['extra_runs'] ?? inning['extras'];
    if (extras == null) return const SizedBox.shrink();
    if (extras is Map) {
      final details = extras.entries.map((e) => '${e.key}: ${e.value}').join(', ');
      return _scorecardLine('Extras: $details');
    }
    return _scorecardLine('Extras: $extras');
  }
  Widget _scorecardYetToBat(Map<String, dynamic> inning) {
    final supplied = inning['yet_to_bat'] ?? inning['yetToBat'] ?? inning['did_not_bat'];
    final names = supplied is List ? supplied.map((e) => e is Map ? (e['name'] ?? e['title'] ?? '').toString() : e.toString()).where((e) => e.isNotEmpty).toList() : <String>[];
    if (names.isEmpty) names.addAll(_scorecardRows(inning['batsmen']).where((p) => '${p['batting']}'.toLowerCase() == 'true').map((p) => (p['name'] ?? '').toString()).where((s) => s.isNotEmpty));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_scorecardHeading('Yet to bat'), _scorecardLine(names.isEmpty ? '—' : names.join(', '))]);
  }
  Widget _scorecardFallOfWickets(Map<String, dynamic> inning) {
    final fows = _scorecardRows(inning['fows']);
    final text = fows.map((f) => '${f['score_at_dismissal'] ?? ''}/${f['number'] ?? ''} (${f['name'] ?? ''}, ${f['overs_at_dismissal'] ?? ''} ov)').join(', ');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_scorecardHeading('Fall of wicket'), _scorecardLine(text.isEmpty ? '—' : text)]);
  }
  Widget _scorecardPartnership(Map<String, dynamic> inning) {
    final partnership = inning['current_partnership'];
    if (partnership is! Map) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_scorecardHeading('Partnership'), _scorecardLine('—')]);
    final batsmen = partnership['batsmen'] is List ? (partnership['batsmen'] as List).whereType<Map>().toList() : <Map>[];
    final first = batsmen.isNotEmpty ? batsmen[0] : const {};
    final second = batsmen.length > 1 ? batsmen[1] : const {};
    final runs = partnership['runs'] ?? 0, balls = partnership['balls'] ?? 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _scorecardHeading('Partnership'),
      Padding(padding: const EdgeInsets.fromLTRB(10, 10, 10, 6), child: Row(children: [Expanded(child: Text('${first['name'] ?? 'Batter'} ${first['runs'] ?? 0}(${first['balls'] ?? 0})', style: const TextStyle(fontSize: 11))), Text('$runs($balls)', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)), Expanded(child: Text('${second['name'] ?? 'Batter'} ${second['runs'] ?? 0}(${second['balls'] ?? 0})', textAlign: TextAlign.right, style: const TextStyle(fontSize: 11)))])),
      ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: _scorecardNumber(runs) == 0 ? 0 : (_scorecardNumber(first['runs']) / _scorecardNumber(runs)).clamp(0, 1).toDouble(), minHeight: 7, backgroundColor: const Color(0xFF4D83FF), color: const Color(0xFF13B981))),
      const SizedBox(height: 14),
    ]);
  }

  Widget _groundStatsContent() => Column(children: [
    Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Row(mainAxisAlignment: MainAxisAlignment.start, children: [
        _statsSubtabChip('Ground', 0),
        const SizedBox(width: 8),
        _statsSubtabChip('Team', 1),
      ]),
    ),
    Expanded(child: _statsSubtab == 0 ? ListView(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
    children: [
      _groundCard(
        title: 'Winning Score - First Innings',
        subtitle: 'Average Winning Score In Innings.',
        future: _groundParScore,
        builder: (data) {
          final average = _numberFor(data, const ['battingFirst', 'batting_first']);
          final remaining = _numberFor(data, const ['remaining']);
          final highest = average != null && remaining != null ? average + remaining : null;
          final stadium = _groundTitle(data);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(stadium, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 7),
            _scoreProgress(average, highest),
          ]);
        },
      ),
      const SizedBox(height: 12),
      _groundCard(
        title: 'Wickets Per Innings',
        subtitle: 'Wicket taken in phases in this ground',
        future: _groundWickets,
        builder: (data) => _WicketsPhaseChart(rows: _wicketPhaseRows(data), title: _groundTitle(data)),
      ),
      const SizedBox(height: 12),
      _groundCard(
        title: 'Win Percentage',
        subtitle: 'Percentage of wins batting first and second',
        future: _groundWinningPercentage,
        builder: (data) {
          final (first, second) = _winningPercentages(data);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(_groundTitle(data), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 7),
            const Text('Win Percentage', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
            const SizedBox(height: 7),
            _winningPercentageBar(first, second),
          ]);
        },
      ),
      const SizedBox(height: 12),
      _groundCard(
        title: 'Run Scored In Phases',
        subtitle: 'Average runs scored while batting in this ground divide in phases',
        future: _groundRunsByPhase,
        builder: (data) => _runsPhaseChart(rows: _runsPhaseRows(data), title: _groundTitle(data)),
      ),
      const SizedBox(height: 12),
      _groundCard(
        title: 'Economy In Phases',
        subtitle: 'Economy in different phases of the game',
        future: _groundEconomyByPhase,
        builder: (data) => _EconomyPhaseChart(rows: _runsPhaseRows(data), title: _groundTitle(data)),
      ),
      const SizedBox(height: 12),
      _groundCard(
        title: 'Boundaries In Phase',
        subtitle: 'Boundaries in different phases of the game',
        future: _groundBoundaries,
        builder: (data) => _BoundariesChart(rows: _boundaryRows(data), title: _groundTitle(data)),
      ),
      _askAiSection(),
    ],
    ) : ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 16), children: [
      _teamChartCard(title: 'Runs By Phases', subtitle: 'Runs scored while batting in phases.', matches: _teamRunMatches, onMatches: (value) => setState(() => _teamRunMatches = value), metric: 'runs'),
      const SizedBox(height: 12),
      _teamChartCard(title: 'Wicket Taken', subtitle: 'Wicket taken while bowling in phases.', matches: _teamWicketMatches, onMatches: (value) => setState(() => _teamWicketMatches = value), metric: 'wickets'),
      const SizedBox(height: 12),
      _teamBoundaryCard(),
      _askAiSection(),
    ])),
  ]);

  Widget _teamChartCard({required String title, required String subtitle, required int matches, required ValueChanged<int> onMatches, required String metric}) => Container(
    padding: const EdgeInsets.all(12), decoration: const BoxDecoration(color: AppColors.surface, border: Border.fromBorderSide(BorderSide(color: AppColors.border))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)), const SizedBox(width: 6), const Icon(Icons.info_outline, size: 16)]),
      const SizedBox(height: 4), Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
      const SizedBox(height: 12), _matchRangeSelector(matches, onMatches), const SizedBox(height: 12),
      Row(
        children: ['Powerplay', 'Middle Over', 'Death Over'].asMap().entries.map((entry) => Expanded(
          child: InkWell(
            onTap: () => setState(() { if (metric == 'runs') { _teamRunPhase = entry.key; } else { _teamWicketPhase = entry.key; } }),
            child: Row(children: [
              Icon(((metric == 'runs' ? _teamRunPhase : _teamWicketPhase) == entry.key) ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 14, color: AppColors.muted),
              const SizedBox(width: 4),
              Flexible(child: Text(entry.value, style: const TextStyle(color: AppColors.muted, fontSize: 10), overflow: TextOverflow.ellipsis)),
            ]),
          ),
        )).toList(),
      ),
      const SizedBox(height: 12),
      FutureBuilder<Object?>(future: _teamAnalysis, builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const SizedBox(height: 300, child: Center(child: CircularProgressIndicator(color: AppColors.acid)));
        if (snapshot.hasError || snapshot.data == null) return const SizedBox(height: 120, child: Center(child: Text('Team stats are not available for this match.', style: TextStyle(color: AppColors.muted, fontSize: 11))));
        final phase = metric == 'runs' ? _teamRunPhase : _teamWicketPhase;
        final teams = _teamMetricRows(snapshot.data, metric, matches, phase);
        return _TeamLineChart(teams: teams, metric: metric == 'runs' ? 'Runs' : 'Wickets', xAxis: 'Last $matches matches (Latest on the left)');
      }),
    ]),
  );

  Widget _matchRangeSelector(int selected, ValueChanged<int> onChanged) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10), decoration: BoxDecoration(border: Border.all(color: AppColors.border)),
    child: DropdownButtonHideUnderline(child: DropdownButton<int>(value: selected, isDense: true, dropdownColor: AppColors.surface, style: const TextStyle(color: Colors.white, fontSize: 12), items: const [5, 10, 20].map((n) => DropdownMenuItem(value: n, child: Text('Last $n Matches'))).toList(), onChanged: (v) { if (v != null) onChanged(v); })),
  );

  Widget _teamBoundaryCard() => Container(
    padding: const EdgeInsets.all(12), decoration: const BoxDecoration(color: AppColors.surface, border: Border.fromBorderSide(BorderSide(color: AppColors.border))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: const [Text('Boundaries Percentage', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)), SizedBox(width: 6), Icon(Icons.info_outline, size: 16)]),
      const SizedBox(height: 4), const Text('Percentage of runs in boundaries for each team', style: TextStyle(color: AppColors.muted, fontSize: 11)),
      const SizedBox(height: 12), Row(children: [for (final entry in ['Batting', 'Bowling'].asMap().entries) Expanded(child: InkWell(onTap: () => setState(() => _teamBoundaryMode = entry.key), child: Row(children: [Icon(_teamBoundaryMode == entry.key ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 15, color: AppColors.muted), const SizedBox(width: 5), Text(entry.value, style: const TextStyle(color: AppColors.muted, fontSize: 11))])))]),
      const SizedBox(height: 12), FutureBuilder<Object?>(future: _teamAnalysis, builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const SizedBox(height: 180, child: Center(child: CircularProgressIndicator(color: AppColors.acid)));
        if (snapshot.hasError || snapshot.data == null) return const SizedBox(height: 90, child: Center(child: Text('Team stats are not available for this match.', style: TextStyle(color: AppColors.muted, fontSize: 11))));
        return _TeamBoundaryChart(teams: _teamBoundaryRows(snapshot.data, _teamBoundaryMode == 0));
      }),
    ]),
  );

  Map? _teamWidget(Object? data, String widgetName) {
    final widgets = data is List ? data : data is Map ? data['value'] : null;
    if (widgets is! List) return null;
    for (final item in widgets.whereType<Map>()) {
      if (item['widgetName'] == widgetName && item['widgets'] is Map) return item['widgets'] as Map;
    }
    return null;
  }

  List<_TeamSeries> _teamMetricRows(Object? data, String metric, int count, int phase) {
    final widgetName = metric == 'runs' ? 'team_average_run_scored' : 'team_wickets_taken';
    final section = _teamWidget(data, widgetName);
    if (section == null) return const [];
    final rangeKey = 'Last_${count}_matches';
    final range = section[rangeKey];
    if (range is! Map) return const [];
    final phaseKey = const ['powerPlay', 'middleOver', 'deathOver'][phase.clamp(0, 2).toInt()];
    final phaseRows = range[phaseKey];
    if (phaseRows is! List || phaseRows.isEmpty || phaseRows.first is! Map) return const [];
    final rows = (phaseRows.first as Map)['data'];
    if (rows is! List) return const [];
    final teamNames = <String>{};
    for (final row in rows.whereType<Map>()) {
      for (final entry in row.entries) {
        if (entry.key.toString() != 'match' && entry.value is num) teamNames.add(entry.key.toString());
      }
    }
    return [
      for (final team in teamNames)
        _TeamSeries(team, [for (final row in rows.whereType<Map>()) if (row[team] is num) row[team] as num]),
    ];
  }

  List<_TeamBoundary> _teamBoundaryRows(Object? data, bool batting) {
    final section = _teamWidget(data, 'team_boundaries_percentage');
    final rows = section?[batting ? 'Batting' : 'Bowling'];
    if (rows is! List) return const [];
    num valueFor(List data, RegExp pattern) {
      for (final item in data.whereType<Map>()) {
        if (pattern.hasMatch(item['match']?.toString() ?? '')) {
          final value = item['value'];
          return value is num ? value : num.tryParse(value?.toString() ?? '') ?? 0;
        }
      }
      return 0;
    }
    return [
      for (final item in rows.whereType<Map>())
        if (item['title'] != null && item['data'] is List)
          _TeamBoundary(
            item['title'].toString(),
            valueFor(item['data'] as List, RegExp(r"4(?:'|’)?s", caseSensitive: false)),
            valueFor(item['data'] as List, RegExp(r"6(?:'|’)?s", caseSensitive: false)),
          ),
    ];
  }

  Widget _statsSubtabChip(String label, int value) => InkWell(
    onTap: () => setState(() => _statsSubtab = value),
    child: Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: _statsSubtab == value ? AppColors.acid : AppColors.surface, border: Border.all(color: _statsSubtab == value ? AppColors.acid : AppColors.border)),
      child: Text(label, style: TextStyle(color: _statsSubtab == value ? AppColors.background : AppColors.muted, fontSize: 11, fontWeight: FontWeight.w600)),
    ),
  );

  Widget _groundCard({required String title, required String subtitle, required Future<Object?> future, required Widget Function(Object?) builder}) => Container(
    margin: const EdgeInsets.only(bottom: 2),
    padding: const EdgeInsets.all(12),
    decoration: const BoxDecoration(color: AppColors.surface, border: Border.fromBorderSide(BorderSide(color: AppColors.border))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
      const SizedBox(height: 4), Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
      const SizedBox(height: 12),
      FutureBuilder<Object?>(future: future, builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const SizedBox(height: 100, child: Center(child: CircularProgressIndicator(color: AppColors.acid)));
        if (snapshot.hasError || snapshot.data == null) return const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('Ground stats are not available for this match.', style: TextStyle(color: AppColors.muted, fontSize: 11)));
        return Container(width: double.infinity, padding: const EdgeInsets.all(12), color: const Color(0xFF292929), child: builder(snapshot.data));
      }),
    ]),
  );

  Widget _scoreValue(String label, num? value) => Column(children: [
    Text(value == null ? '—' : value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), ''), style: const TextStyle(color: AppColors.acid, fontSize: 18, fontWeight: FontWeight.w800)),
    Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 10)),
  ]);

  Widget _scoreProgress(num? average, num? highest) {
    final progress = average == null || highest == null || highest <= 0 ? 0.0 : (average / highest).clamp(0, 1).toDouble();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        _scoreValue('Average', average),
        _scoreValue('Highest', highest),
      ]),
      const SizedBox(height: 10),
      ClipRRect(borderRadius: BorderRadius.circular(10), child: LinearProgressIndicator(value: progress, minHeight: 12, backgroundColor: AppColors.border, valueColor: const AlwaysStoppedAnimation<Color>(AppColors.acid))),
      const SizedBox(height: 4),
      const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('0', style: TextStyle(color: AppColors.muted, fontSize: 9)),
        Text('Highest', style: TextStyle(color: AppColors.muted, fontSize: 9)),
      ]),
    ]);
  }

  (num?, num?) _winningPercentages(Object? data) {
    num? first;
    num? second;
    num? parse(Object? value) => value is num ? value : num.tryParse(value?.toString() ?? '');
    void visit(Object? value) {
      if (value is Map) {
        final normalized = <String, Object?>{
          for (final entry in value.entries)
            entry.key.toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ''): entry.value,
        };
        if (normalized.containsKey('battingfirst')) first ??= parse(normalized['battingfirst']);
        if (normalized.containsKey('battingsecond')) second ??= parse(normalized['battingsecond']);
        final label = (normalized['match'] ?? normalized['label'] ?? normalized['name'] ?? normalized['innings'])?.toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        if (label == 'battingfirst' || label == 'firstinnings') first ??= parse(normalized['value'] ?? normalized['percentage'] ?? normalized['winpercentage']);
        if (label == 'battingsecond' || label == 'secondinnings') second ??= parse(normalized['value'] ?? normalized['percentage'] ?? normalized['winpercentage']);
        for (final entry in value.entries) {
          visit(entry.value);
        }
      } else if (value is List) {
        for (final item in value) {
          visit(item);
        }
      }
    }
    visit(data);
    return (first, second);
  }

  Widget _winningPercentageBar(num? first, num? second) {
    final firstValue = (first ?? 0).clamp(0, 100).toDouble();
    final secondValue = (second ?? 0).clamp(0, 100).toDouble();
    final total = firstValue + secondValue;
    final firstFraction = total == 0 ? .5 : firstValue / total;
    final secondFraction = total == 0 ? .5 : secondValue / total;
    String label(num? value) => value == null ? '—%' : '${value.toStringAsFixed(0)}%';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label(first), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
        Text(label(second), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
      ]),
      const SizedBox(height: 6),
      SizedBox(
        width: double.infinity,
        height: 12,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Row(
            children: [
              Expanded(
                flex: (firstFraction * 1000).round().clamp(1, 1000).toInt(),
                child: const SizedBox.expand(child: ColoredBox(color: Color(0xFF38C985))),
              ),
              Expanded(
                flex: (secondFraction * 1000).round().clamp(1, 1000).toInt(),
                child: const SizedBox.expand(child: ColoredBox(color: Color(0xFF2863A5))),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 5),
      const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('Batting First', style: TextStyle(fontSize: 9)),
        Text('Batting Second', style: TextStyle(fontSize: 9)),
      ]),
    ]);
  }

  num? _numberFor(Object? data, List<String> keys) {
    final sought = keys.map((key) => key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')).toSet();
    Object? find(Object? value) {
      if (value is Map) {
        for (final entry in value.entries) {
          if (sought.contains(entry.key.toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ''))) return entry.value;
        }
        for (final entry in value.values) { final result = find(entry); if (result != null) return result; }
      } else if (value is List) {
        for (final item in value) { final result = find(item); if (result != null) return result; }
      }
      return null;
    }
    final value = find(data);
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? '');
  }

  String _groundTitle(Object? data) {
    const names = {'groundname', 'stadiumname', 'venuename', 'ground', 'venue', 'stadium', 'title'};
    Object? find(Object? value) {
      if (value is Map) {
        for (final entry in value.entries) {
          if (names.contains(entry.key.toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')) && entry.value is String && entry.value.toString().trim().isNotEmpty) return entry.value;
        }
        for (final entry in value.values) { final result = find(entry); if (result != null) return result; }
      } else if (value is List) {
        for (final item in value) { final result = find(item); if (result != null) return result; }
      }
      return null;
    }
    final title = find(data);
    if (title != null) return title.toString();
    return widget.match.venue.isNotEmpty ? widget.match.venue : 'Ground';
  }

  List<_WicketPhase> _wicketPhaseRows(Object? data) {
    final rows = <_WicketPhase>[];
    if (data is Map) {
      final widgets = data['widgets'];
      if (widgets is Map) {
        final first = _phaseValues(widgets['firstInnings']);
        final second = _phaseValues(widgets['secondInnings']);
        final names = <String>{...first.keys, ...second.keys};
        if (names.isNotEmpty) {
          const order = ['power play', 'middle', 'death', 'in 20 overs'];
          final sorted = names.toList()..sort((a, b) {
            final ai = order.indexOf(a.toLowerCase()), bi = order.indexOf(b.toLowerCase());
            if (ai < 0 && bi < 0) return a.compareTo(b);
            if (ai < 0) return 1;
            if (bi < 0) return -1;
            return ai.compareTo(bi);
          });
          return [for (final name in sorted) _WicketPhase(name, first[name] ?? 0, second[name] ?? 0)];
        }
      }
    }
    void visit(Object? value) {
      if (value is List) { for (final item in value) { visit(item); } return; }
      if (value is! Map) return;
      final map = Map<String, dynamic>.from(value);
      final phaseValue = map['phase'] ?? map['name'] ?? map['overPhase'] ?? map['over_phase'] ?? map['category'];
      if (phaseValue != null) {
        num? read(List<String> keys) {
          for (final key in keys) { final raw = map[key]; if (raw is num) return raw; final parsed = num.tryParse(raw?.toString() ?? ''); if (parsed != null) return parsed; }
          return null;
        }
        final first = read(['firstInning', 'first_inning', 'firstInnings', 'first_innings', 'firstInningWickets', 'first_innings_wickets', 'first', 'innings1', 'inning1']);
        final second = read(['secondInning', 'second_inning', 'secondInnings', 'second_innings', 'secondInningWickets', 'second_innings_wickets', 'second', 'innings2', 'inning2']);
        if (first != null || second != null) rows.add(_WicketPhase(phaseValue.toString(), first ?? 0, second ?? 0));
      }
      for (final entry in map.entries) { if (entry.value is Map || entry.value is List) visit(entry.value); }
    }
    visit(data);
    return rows;
  }

  List<_RunsPhase> _runsPhaseRows(Object? data) {
    if (data is! Map || data['widgets'] is! Map) return const [];
    final widgets = data['widgets'] as Map;
    final first = _phaseValues(widgets['firstInnings']);
    final second = _phaseValues(widgets['secondInnings']);
    const order = ['power play', 'middle', 'death', 'in 20 overs'];
    final names = <String>{...first.keys, ...second.keys}.toList()
      ..sort((a, b) {
        final ai = order.indexOf(a.toLowerCase()), bi = order.indexOf(b.toLowerCase());
        if (ai < 0 && bi < 0) return a.compareTo(b);
        if (ai < 0) return 1;
        if (bi < 0) return -1;
        return ai.compareTo(bi);
      });
    return [for (final name in names) _RunsPhase(name, first[name] ?? 0, second[name] ?? 0)];
  }

  List<_BoundaryValues> _boundaryRows(Object? data) {
    if (data is! Map || data['widgets'] is! Map) return const [];
    final widgets = data['widgets'] as Map;
    Map<String, num> values(Object? innings) {
      final raw = _phaseValues(innings);
      final normalized = <String, num>{};
      for (final entry in raw.entries) {
        normalized[entry.key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')] = entry.value;
      }
      final fours = normalized['4s'] ?? normalized['fours'] ?? normalized['four'] ?? 0;
      final sixes = normalized['6s'] ?? normalized['sixes'] ?? normalized['six'] ?? 0;
      return {'fours': fours, 'sixes': sixes};
    }
    final first = values(widgets['firstInnings']);
    final second = values(widgets['secondInnings']);
    return [
      _BoundaryValues('First Innings', first['fours'] ?? 0, first['sixes'] ?? 0),
      _BoundaryValues('Second Innings', second['fours'] ?? 0, second['sixes'] ?? 0),
    ];
  }

  Map<String, num> _phaseValues(Object? innings) {
    final values = <String, num>{};
    if (innings is! List) return values;
    for (final entry in innings.whereType<Map>()) {
      final data = entry['data'];
      if (data is! List) continue;
      for (final item in data.whereType<Map>()) {
        final phase = item['match']?.toString();
        final raw = item['value'];
        final value = raw is num ? raw : num.tryParse(raw?.toString() ?? '');
        if (phase != null && value != null) values[phase] = value;
      }
    }
    return values;
  }

  Widget _WicketsPhaseChart({required List<_WicketPhase> rows, required String title}) {
    if (rows.isEmpty) return const SizedBox(height: 90, child: Center(child: Text('No wicket phase data available.', style: TextStyle(color: AppColors.muted, fontSize: 11))));
    return Column(children: [
      Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _ChartLegend(color: Color(0xFF5B8FF9), label: 'First Innings'), SizedBox(width: 12), _ChartLegend(color: Color(0xFF34D399), label: 'Second Innings'),
      ]),
      const SizedBox(height: 12),
      SizedBox(height: 230, child: CustomPaint(size: const Size(double.infinity, 230), painter: _WicketsPainter(rows))),
      Row(children: rows.map((row) => Expanded(child: Padding(padding: const EdgeInsets.only(top: 8), child: Column(children: [Text(row.name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)), Text(_phaseOvers(row.name), textAlign: TextAlign.center, style: const TextStyle(fontSize: 9, color: AppColors.muted))])))).toList()),
    ]);
  }

  Widget _runsPhaseChart({required List<_RunsPhase> rows, required String title}) {
    if (rows.isEmpty) return const SizedBox(height: 90, child: Center(child: Text('No run phase data available.', style: TextStyle(color: AppColors.muted, fontSize: 11))));
    return Column(children: [
      Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _ChartLegend(color: Color(0xFF5B8FF9), label: 'First Innings'), SizedBox(width: 12), _ChartLegend(color: Color(0xFF34D399), label: 'Second Innings'),
      ]),
      const SizedBox(height: 8),
      SizedBox(height: 270, child: CustomPaint(size: const Size(double.infinity, 270), painter: _RunsPhasePainter(rows))),
    ]);
  }

  Widget _EconomyPhaseChart({required List<_RunsPhase> rows, required String title}) {
    if (rows.isEmpty) return const SizedBox(height: 90, child: Center(child: Text('No economy phase data available.', style: TextStyle(color: AppColors.muted, fontSize: 11))));
    return Column(children: [
      Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _ChartLegend(color: Color(0xFF5B8FF9), label: 'First Innings'), SizedBox(width: 12), _ChartLegend(color: Color(0xFF34D399), label: 'Second Innings'),
      ]),
      const SizedBox(height: 8),
      SizedBox(height: 250, child: CustomPaint(size: const Size(double.infinity, 250), painter: _EconomyPhasePainter(rows))),
    ]);
  }

  Widget _BoundariesChart({required List<_BoundaryValues> rows, required String title}) {
    if (rows.isEmpty) return const SizedBox(height: 90, child: Center(child: Text('No boundary data available.', style: TextStyle(color: AppColors.muted, fontSize: 11))));
    return Column(children: [
      Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _ChartLegend(color: Color(0xFF5B8FF9), label: 'First Innings'), SizedBox(width: 12), _ChartLegend(color: Color(0xFF34D399), label: 'Second Innings'),
      ]),
      const SizedBox(height: 14),
      Row(children: rows.map((row) => Expanded(child: Column(children: [
        Text(row.innings, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        SizedBox(height: 126, child: Center(child: SizedBox(width: 126, height: 126, child: Stack(alignment: Alignment.center, children: [
          CustomPaint(size: const Size(126, 126), painter: _BoundaryDonutPainter(row.fours, row.sixes)),
          Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Total', style: TextStyle(fontSize: 9)),
            const Text('Boundaries', style: TextStyle(fontSize: 9)),
            Text((row.fours + row.sixes).toStringAsFixed(2), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
          ]),
        ])))),
        const SizedBox(height: 8),
        _BoundaryLegend(color: _BoundaryDonutPainter.foursColor, label: 'Fours ${row.fours.toStringAsFixed(2)}'),
        const SizedBox(height: 4),
        _BoundaryLegend(color: _BoundaryDonutPainter.sixesColor, label: 'Sixes ${row.sixes.toStringAsFixed(2)}'),
      ]))).toList()),
    ]);
  }

  String _phaseOvers(String phase) => switch (phase.toLowerCase()) {
    'powerplay' || 'power play' => '(0-6 Overs)', 'middle' => '(7-15 Overs)', 'death' => '(15-20 Overs)', 'total' || 'in 20 overs' => '(In 20 Overs)', _ => '',
  };

  Widget _preMatchReportContent() => FutureBuilder<Object?>(
    future: _preMatchReport,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) return _askAiStatus('', loading: true);
      if (snapshot.hasError) return _askAiStatus('Could not load match report.');
      if (snapshot.data == null) return _askAiStatus('No match report available.');
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Pre-match Report', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          _reportValue(snapshot.data),
          _askAiSection(),
        ]),
      );
    },
  );

  Widget _reportValue(Object? value, {String? label}) {
    if (value == null) return const SizedBox.shrink();
    if (value is Map) {
      final entries = value.entries.where((entry) => entry.value != null).toList();
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final entry in entries)
          Padding(padding: const EdgeInsets.only(bottom: 8), child: _reportValue(entry.value, label: _reportLabel(entry.key.toString()))),
      ]);
    }
    if (value is List) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (label != null) Padding(padding: const EdgeInsets.only(bottom: 5), child: Text(label, style: const TextStyle(color: AppColors.acid, fontSize: 12, fontWeight: FontWeight.w700))),
        for (final item in value) Padding(padding: const EdgeInsets.only(bottom: 6), child: _reportValue(item)),
      ]);
    }
    final text = value.toString().trim();
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: const BoxDecoration(color: AppColors.surface, border: Border.fromBorderSide(BorderSide(color: AppColors.border))),
      child: label == null
          ? Text(text, style: const TextStyle(fontSize: 12, height: 1.4))
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(color: AppColors.acid, fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 5),
              Text(text, style: const TextStyle(fontSize: 12, height: 1.4)),
            ]),
    );
  }

  String _reportLabel(String key) => key
      .replaceAll(RegExp(r'([a-z])([A-Z])'), r'$1 $2')
      .replaceAll('_', ' ')
      .replaceAll('-', ' ')
      .split(' ')
      .where((word) => word.isNotEmpty)
      .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
      .join(' ');

  Widget _squadsContent() => Column(children: [
    const SizedBox(height: 12),
    SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
      _squadChip('Whole Squad', 0), const SizedBox(width: 8), _squadChip('Top Batter', 1), const SizedBox(width: 8), _squadChip('Top Bowler', 2),
    ])),
    const SizedBox(height: 12),
    if (_squadFilter == 1 || _squadFilter == 2) ...[
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Row(children: [
        Expanded(child: _batterModeChip(_squadFilter == 1 ? 'Top Batter' : 'Top Bowler', 0)),
        const SizedBox(width: 8),
        Expanded(child: _batterModeChip(_squadFilter == 1 ? 'Batter Vs Bowler' : 'Bowler Vs Batter', 1)),
      ])),
      const SizedBox(height: 10),
      if (_batterSubtab == 0) ...[
        Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 10), child: Align(alignment: Alignment.centerLeft, child: Text(_squadFilter == 1 ? 'Top Batsman Probabilities' : 'Top Bowler Probabilities', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Row(children: [
          Expanded(child: _batterDropdown<int>(value: _squadFilter == 1 ? _batterMetric : _bowlerMetric, items: List.generate(_squadFilter == 1 ? _batterMetrics.length : _bowlerMetrics.length, (i) => DropdownMenuItem(value: i, child: Text(_squadFilter == 1 ? _batterMetrics[i] : _bowlerMetrics[i]))), onChanged: _squadFilter == 1 ? _selectBatterMetric : _selectBowlerMetric)),
          const SizedBox(width: 8),
          Expanded(child: _batterDropdown<int>(value: _squadFilter == 1 ? _batterThreshold : _bowlerThreshold, items: List.generate(_squadFilter == 1 ? _batterThresholds.length : _bowlerThresholds.length, (i) => DropdownMenuItem(value: i, child: Text(_squadFilter == 1 ? _batterThresholds[i] : _bowlerThresholds[i]))), onChanged: _squadFilter == 1 ? _selectBatterThreshold : _selectBowlerThreshold)),
        ])),
      ] else if (_squadFilter == 1)
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: FutureBuilder<List<Map<String, dynamic>>>(future: _players, builder: (context, playerSnapshot) {
          final players = playerSnapshot.data ?? [];
          final identifiedPlayers = players.where((player) => _batsmanId(player) != null).toList();
          if (playerSnapshot.connectionState == ConnectionState.waiting) return const LinearProgressIndicator(color: AppColors.acid);
          if (playerSnapshot.hasError || identifiedPlayers.isEmpty) return const Text('No players available for comparison', style: TextStyle(color: AppColors.muted, fontSize: 11));
          final selectedId = identifiedPlayers.any((p) => _batsmanId(p) == _selectedBatsmanId) ? _selectedBatsmanId : null;
          return Row(children: [
            Expanded(child: _batterDropdown<String?>(value: selectedId, items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Select batter')),
              ...identifiedPlayers.map((player) => DropdownMenuItem<String?>(value: _batsmanId(player)!, child: Text(_playerName(player), overflow: TextOverflow.ellipsis))),
            ], onChanged: _selectComparisonPlayer)),
            const SizedBox(width: 8),
            Expanded(child: _batterDropdown<int>(value: _comparisonMetric, items: List.generate(_comparisonMetrics.length, (i) => DropdownMenuItem(value: i, child: Text(_comparisonMetrics[i]))), onChanged: _selectComparisonMetric)),
          ]);
        }))
      else
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: FutureBuilder<List<Map<String, dynamic>>>(future: _players, builder: (context, playerSnapshot) {
          final players = (playerSnapshot.data ?? []).where((p) => _isBowlerOrAllRounder(p) && _playerId(p) != null).toList();
          if (playerSnapshot.connectionState == ConnectionState.waiting) return const LinearProgressIndicator(color: AppColors.acid);
          if (playerSnapshot.hasError) return const Text('Could not load bowlers', style: TextStyle(color: AppColors.muted, fontSize: 11));
          final selectedId = players.any((p) => _playerId(p) == _selectedBowlerId) ? _selectedBowlerId : null;
          final defaultBowlerId = selectedId ?? (players.isNotEmpty ? _playerId(players.first) : null);
          if (!_bowlerDefaultApplied && _selectedBowlerId == null && defaultBowlerId != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || _bowlerDefaultApplied || _selectedBowlerId != null) return;
              _bowlerDefaultApplied = true;
              _selectedBowlerId = defaultBowlerId;
              if (_batterSubtab == 1 && _squadFilter == 2) _loadBowlerComparison();
              setState(() {});
            });
          }
          return Row(children: [
            Expanded(child: _batterDropdown<String?>(value: defaultBowlerId, items: [const DropdownMenuItem<String?>(value: null, child: Text('Select Bowler')), ...players.map((p) => DropdownMenuItem<String?>(value: _playerId(p), child: Text(_playerName(p), overflow: TextOverflow.ellipsis)))], onChanged: _selectBowler)),
            const SizedBox(width: 8),
            Expanded(child: _batterDropdown<int>(value: _bowlerComparisonMetric, items: List.generate(_bowlerComparisonMetrics.length, (i) => DropdownMenuItem(value: i, child: Text(_bowlerComparisonMetrics[i]))), onChanged: _selectBowlerComparisonMetric)),
          ]);
        })),
    ],
    Expanded(child: (_squadFilter == 1 || _squadFilter == 2) && _batterSubtab == 1
      ? _comparisonResults(isBowler: _squadFilter == 2)
      : FutureBuilder<List<Map<String, dynamic>>>(future: _squadFilter == 1 ? _topBatters : _squadFilter == 2 ? _topBowlers : _players, builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) return _askAiStatus('', loading: true);
      if (snapshot.hasError) return _askAiStatus(_squadFilter == 1 ? 'Could not load top batter data.' : 'Could not load players.');
      final players = snapshot.data ?? [];
      if (_squadFilter == 1 || _squadFilter == 2) {
        if (players.isEmpty) return _askAiStatus(_squadFilter == 1 ? 'No top batter data available.' : 'No top bowler data available.');
        return ListView.builder(itemCount: players.length + 1, itemBuilder: (context, index) => index == players.length ? _askAiSection() : _topBatterRow(players[index]));
      }
      final filtered = players.where((player) {
        final role = '${player['role'] ?? player['playingRole'] ?? player['playing_role'] ?? player['position'] ?? ''}'.toLowerCase();
        if (_squadFilter == 1) return role.contains('bat');
        if (_squadFilter == 2) return role.contains('bowl');
        return true;
      }).toList();
      if (filtered.isEmpty) return _askAiStatus(players.isEmpty ? 'No squad information available.' : 'No players in this category.');
      if (_squadFilter == 0) return _wholeSquad(players);
      return ListView.builder(itemCount: filtered.length + 1, itemBuilder: (context, index) {
        if (index == filtered.length) return _askAiSection();
        final player = filtered[index];
        final name = (player['playerName'] ?? player['player_name'] ?? player['fullName'] ?? player['name'] ?? 'Player').toString();
        final role = _squadRoleLabel(player);
        final team = (player['_teamLabel'] ?? player['teamName'] ?? player['team_name'] ?? '').toString();
        final image = (player['image'] ?? player['imageUrl'] ?? player['image_url'] ?? player['photo'] ?? player['thumb_url'] ?? '').toString();
        return Container(decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))), child: ListTile(
          dense: true, leading: CircleAvatar(radius: 18, backgroundColor: AppColors.surface, backgroundImage: image.isNotEmpty ? NetworkImage(image) : null, child: image.isEmpty ? const Icon(Icons.person, size: 20, color: AppColors.muted) : null),
          title: Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          subtitle: Text([if (team.isNotEmpty) team, role.isEmpty ? 'Player' : role].join(' • '), style: const TextStyle(fontSize: 11, color: AppColors.muted)),
        ));
      });
    })),
  ]);

  Widget _wholeSquad(List<Map<String, dynamic>> players) {
    final teamA = _playersForTeam(players, 'A');
    final teamB = _playersForTeam(players, 'B');
    final unassigned = players.where((player) => !_belongsToTeam(player, 'A') && !_belongsToTeam(player, 'B')).toList();
    return ListView(children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: _squadTeamColumn('A', teamA)),
        Container(width: 1, color: AppColors.border),
        Expanded(child: _squadTeamColumn('B', teamB)),
      ]),
      if (unassigned.isNotEmpty) ...[
        const Divider(color: AppColors.border, height: 1),
        Padding(padding: const EdgeInsets.all(8), child: Text('Other players', style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w600))),
        ...unassigned.map((player) => _squadPlayerRow(player)),
      ],
      _askAiSection(),
    ]);
  }

  List<Map<String, dynamic>> _playersForTeam(List<Map<String, dynamic>> players, String side) => players.where((player) => _belongsToTeam(player, side)).toList();

  bool _belongsToTeam(Map<String, dynamic> player, String side) {
    final labelValue = player['_teamLabel'] ?? player['teamName'] ?? player['team_name'] ?? player['team'];
    final label = labelValue is Map
        ? (labelValue['name'] ?? labelValue['shortName'] ?? labelValue['short_name'] ?? labelValue['id'] ?? '').toString()
        : (labelValue ?? '').toString();
    if (label.isEmpty) return false;
    String normalize(String value) => value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final normalizedLabel = normalize(label);
    final team = widget.match.raw['team$side'];
    final aliases = <String>{widget.match.teamName(side, scorecard: widget.scorecard), 'team$side', 'team ${side.toLowerCase()}'};
    if (team is Map) {
      for (final key in ['name', 'shortName', 'short_name', 'teamName', 'team_name', 'id', 'teamId', 'team_id']) {
        final value = team[key];
        if (value != null) aliases.add(value.toString());
      }
    } else if (team != null) {
      aliases.add(team.toString());
    }
    final scorecardTeam = widget.match._scorecardTeam(widget.scorecard, side);
    if (scorecardTeam != null) {
      for (final key in ['name', 'short_name', 'team_id', 'id']) {
        final value = scorecardTeam[key];
        if (value != null) aliases.add(value.toString());
      }
    }
    return aliases.any((alias) {
      final normalizedAlias = normalize(alias);
      return normalizedAlias.isNotEmpty && (normalizedLabel == normalizedAlias || (normalizedAlias.length > 3 && normalizedLabel.contains(normalizedAlias)) || (normalizedLabel.length > 3 && normalizedAlias.contains(normalizedLabel)));
    });
  }

  Widget _squadTeamColumn(String side, List<Map<String, dynamic>> players) {
    final name = widget.match.teamName(side, scorecard: widget.scorecard);
    final logo = widget.match.teamFlag(side, scorecard: widget.scorecard);
    final rightAlign = side == 'B';
    return Column(children: [
      Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        color: AppColors.surface,
        child: Row(children: rightAlign ? [
          Expanded(child: Text(name, textAlign: TextAlign.right, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
          const SizedBox(width: 6),
          if (logo != null && logo.isNotEmpty) ClipOval(child: Image.network(logo, width: 22, height: 22, fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.shield, size: 20, color: AppColors.muted))) else const Icon(Icons.shield, size: 20, color: AppColors.muted),
        ] : [
          if (logo != null && logo.isNotEmpty) ClipOval(child: Image.network(logo, width: 22, height: 22, fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.shield, size: 20, color: AppColors.muted))) else const Icon(Icons.shield, size: 20, color: AppColors.muted),
          const SizedBox(width: 6),
          Expanded(child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
        ]),
      ),
      const Divider(height: 1, color: AppColors.border),
      if (players.isEmpty)
        const Padding(padding: EdgeInsets.all(12), child: Center(child: Text('No players listed', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 11))))
      else
        for (var index = 0; index < players.length; index++) ...[
          if (index > 0) const Divider(height: 1, color: AppColors.border),
          _squadPlayerRow(players[index], alignRight: rightAlign),
        ],
    ]);
  }

  Widget _squadPlayerRow(Map<String, dynamic> player, {bool alignRight = false}) {
    final name = _playerName(player);
    final role = _squadRoleLabel(player);
    final image = (player['image'] ?? player['imageUrl'] ?? player['image_url'] ?? player['photo'] ?? player['thumb_url'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
      child: Row(children: alignRight ? [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(name, textAlign: TextAlign.right, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(role, textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: AppColors.muted)),
        ])),
        const SizedBox(width: 6),
        CircleAvatar(radius: 16, backgroundColor: AppColors.surface, backgroundImage: image.isNotEmpty ? NetworkImage(image) : null, child: image.isEmpty ? const Icon(Icons.person, size: 18, color: AppColors.muted) : null),
      ] : [
        CircleAvatar(radius: 16, backgroundColor: AppColors.surface, backgroundImage: image.isNotEmpty ? NetworkImage(image) : null, child: image.isEmpty ? const Icon(Icons.person, size: 18, color: AppColors.muted) : null),
        const SizedBox(width: 6),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(role, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: AppColors.muted)),
        ])),
      ]),
    );
  }

  String _squadRoleLabel(Map<String, dynamic> player) {
    final roles = player['playingRoles'] ?? player['playingRole'] ?? player['playing_role'] ?? player['role'] ?? player['position'];
    final roleValues = roles is List ? roles : (roles == null ? const [] : roles.toString().split(RegExp(r'[,/]')));
    final normalizedRoles = roleValues.map((role) => role.toString().trim().toLowerCase()).toSet();

    Object? style;
    if (normalizedRoles.contains('wk') || normalizedRoles.contains('wicketkeeper') || normalizedRoles.contains('wicket keeper')) {
      return 'Wicket Keeper';
    } else if (normalizedRoles.contains('bowl')) {
      style = player['longBowlingStyles'];
    } else if (normalizedRoles.contains('bat') || normalizedRoles.contains('all')) {
      style = player['longBattingStyles'];
    }

    if (style is List) {
      final label = style.map((value) => value.toString()).where((value) => value.trim().isNotEmpty).join(', ');
      if (label.isNotEmpty) return label;
    }
    if (style is Map) {
      final label = (style['name'] ?? style['label'] ?? style['value'] ?? '').toString().trim();
      if (label.isNotEmpty) return label;
    }
    final label = style?.toString().trim() ?? '';
    if (label.isNotEmpty && label.toLowerCase() != 'null') return label;
    if (normalizedRoles.contains('all')) return 'Allrounder';
    if (normalizedRoles.contains('bowl')) return 'Bowler';
    if (normalizedRoles.contains('bat')) return 'Batter';
    return 'Player';
  }

  String? _batsmanId(Map<String, dynamic> player) => (player['playerId'] ?? player['player_id'] ?? player['batsmanId'] ?? player['batsman_id'] ?? player['id'])?.toString();
  String? _playerId(Map<String, dynamic> player) => (player['playerId'] ?? player['player_id'] ?? player['id'])?.toString();
  bool _isBowlerOrAllRounder(Map<String, dynamic> player) {
    final roles = player['playingRoles'] ?? player['playingRole'] ?? player['playing_role'] ?? player['role'] ?? player['position'];
    final text = roles is List ? roles.join(' ').toLowerCase() : '${roles ?? ''}'.toLowerCase();
    return text.contains('bowl') || text.contains('allround') || text.contains('all-round');
  }
  String _playerName(Map<String, dynamic> player) => (player['playerName'] ?? player['player_name'] ?? player['fullName'] ?? player['name'] ?? 'Player').toString();

  Widget _batterModeChip(String label, int value) => InkWell(
    onTap: () => setState(() {
      _batterSubtab = value;
      if (value == 1) {
        if (_squadFilter == 2) {
          _loadBowlerComparison();
        } else {
          _loadBatterComparison();
        }
      }
    }),
    child: Container(height: 32, alignment: Alignment.center, decoration: BoxDecoration(color: _batterSubtab == value ? const Color(0xFF292929) : AppColors.surface, border: Border.all(color: _batterSubtab == value ? AppColors.border : AppColors.border)), child: Text(label, style: TextStyle(fontSize: 11, color: _batterSubtab == value ? Colors.white : AppColors.muted))),
  );

  Widget _comparisonResults({bool isBowler = false}) => FutureBuilder<Object?>(future: isBowler ? _bowlerComparison : _batterComparison, builder: (context, snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) return _askAiStatus('', loading: true);
    if (snapshot.hasError) return _askAiStatus('Could not load batter comparison.');
    final rows = _comparisonRows(snapshot.data, isBowler: isBowler);
    if (!isBowler && _selectedBatsmanId == null) return _askAiStatus('Select a batter to view comparison.');
    if (rows.isEmpty) return _askAiStatus('No comparison data available.');
    return ListView(
      children: [
        ...rows.map((row) => Container(
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
        child: ListTile(
          dense: true,
          title: Text(row.$1, style: const TextStyle(fontSize: 12)),
          subtitle: Text((isBowler ? _bowlerComparisonMetric : _comparisonMetric) == 0 ? 'Probable Dismissal Rate' : 'Probable Strike Rate', style: const TextStyle(fontSize: 10, color: AppColors.muted)),
          trailing: Text(row.$2, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.acid)),
        ),
        )),
        _askAiSection(),
      ],
    );
  });

  List<(String, String)> _comparisonRows(Object? data, {String? inheritedBowler, bool isBowler = false}) {
    if (data is List) {
      return [for (final item in data) ..._comparisonRows(item, inheritedBowler: inheritedBowler, isBowler: isBowler)];
    }
    if (data is! Map) return [];
    final map = Map<String, dynamic>.from(data);
    final bowler = (map['playerName'] ?? map['player_name'] ?? map['bowlerName'] ?? map['bowler_name'] ?? map['bowler'] ?? map['fullName'] ?? map['name'] ?? inheritedBowler)?.toString();
    final metricProbability = (isBowler ? _bowlerComparisonMetric : _comparisonMetric) == 0
        ? (map['probableDismissalRate'] ?? map['probable_dismissal_rate'])
        : (map['probableStrikeRate'] ?? map['probable_strike_rate']);
    final probability = metricProbability ?? map['probability'] ?? map['dismissalProbability'] ?? map['dismissal_probability'] ?? map['strikeRate'] ?? map['strike_rate'] ?? map['probabilityPercentage'] ?? map['percentage'] ?? map['value'];
    if (bowler != null && probability != null && probability is! Map && probability is! List) {
      final value = probability.toString();
      return [(bowler, value.contains('%') ? value : '$value%')];
    }
    final rows = <(String, String)>[];
    for (final key in ['data', 'results', 'bowlers', 'comparisons']) {
      if (map[key] != null) rows.addAll(_comparisonRows(map[key], inheritedBowler: inheritedBowler, isBowler: isBowler));
    }
    if (rows.isNotEmpty) return rows;
    for (final entry in map.entries) {
      if (const {'code', 'message', 'squadAnnounced', 'squad_announced'}.contains(entry.key)) continue;
      if (entry.value is Map || entry.value is List) {
        rows.addAll(_comparisonRows(entry.value, inheritedBowler: entry.key, isBowler: isBowler));
      } else if (entry.value != null && inheritedBowler == null) {
        // Some responses encode each bowler as a map key and probability as its value.
        final value = entry.value.toString();
        rows.add((entry.key, value.contains('%') ? value : '$value%'));
      }
    }
    return rows;
  }

  Widget _batterDropdown<T>({required T value, required List<DropdownMenuItem<T>> items, required ValueChanged<T?> onChanged}) => DropdownButtonFormField<T>(
    initialValue: value,
    isExpanded: true,
    dropdownColor: AppColors.surface,
    style: const TextStyle(color: Colors.white, fontSize: 11),
    decoration: const InputDecoration(filled: true, fillColor: AppColors.surface, contentPadding: EdgeInsets.symmetric(horizontal: 9, vertical: 5), enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.border), borderRadius: BorderRadius.zero), focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.acid), borderRadius: BorderRadius.zero)),
    items: items,
    onChanged: onChanged,
  );

  Widget _topBatterRow(Map<String, dynamic> player) {
    final name = (player['playerName'] ?? player['player_name'] ?? player['fullName'] ?? player['name'] ?? player['batsmanName'] ?? 'Player').toString();
    final image = (player['image'] ?? player['imageUrl'] ?? player['image_url'] ?? player['photo'] ?? player['thumb_url'] ?? '').toString();
    final probability = player['probability'] ?? player['percentage'] ?? player['score'] ?? player['value'] ?? player['probabilityPercentage'];
    final display = probability == null ? '' : probability.toString().contains('%') ? probability.toString() : '$probability%';
    return Container(decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))), child: ListTile(
      dense: true,
      leading: CircleAvatar(radius: 18, backgroundColor: AppColors.surface, backgroundImage: image.isNotEmpty ? NetworkImage(image) : null, child: image.isEmpty ? const Icon(Icons.person, size: 20, color: AppColors.muted) : null),
      title: Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      trailing: Text(display, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
    ));
  }

  Widget _squadChip(String label, int index) => InkWell(onTap: () => setState(() {
    _squadFilter = index;
    if (index == 1) _loadTopBatters();
    if (index == 2) _loadTopBowlers();
  }), child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(color: _squadFilter == index ? AppColors.acid : AppColors.surface, border: Border.all(color: _squadFilter == index ? AppColors.acid : AppColors.border)),
    child: Text(label, style: TextStyle(color: _squadFilter == index ? Colors.black : AppColors.muted, fontSize: 11, fontWeight: FontWeight.w600)),
  ));

  Widget _detailTeam(MatchData match, String side, {bool rightAlign = false, Map<String, dynamic>? scorecard}) {
    final name = match.teamName(side, scorecard: scorecard);
    final logo = match.teamFlag(side, scorecard: scorecard);
    final score = match.teamScore(side, scorecard: scorecard);
    final overs = match.teamOvers(side, scorecard: scorecard);
    final badge = logo == null || logo.isEmpty
        ? const Icon(Icons.shield, size: 25, color: AppColors.muted)
        : ClipOval(child: Image.network(logo, width: 25, height: 25, fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.shield, size: 25, color: AppColors.muted)));
    return Column(crossAxisAlignment: rightAlign ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: rightAlign ? MainAxisAlignment.end : MainAxisAlignment.start, children: [
        if (!rightAlign) ...[badge, const SizedBox(width: 7)],
        Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 20))),
        if (rightAlign) ...[const SizedBox(width: 7), badge],
      ]),
      if (score != 'Yet to bat')
        Padding(padding: EdgeInsets.only(top: 3, left: rightAlign ? 0 : 32, right: rightAlign ? 32 : 0), child: Text('$score${overs.isEmpty ? '' : ' ($overs ov)'}', textAlign: rightAlign ? TextAlign.right : TextAlign.left, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
    ]);
  }

  String _detailTime(DateTime date) {
    final local = date.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    return '${hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')} ${local.hour >= 12 ? 'PM' : 'AM'}';
  }

  String _detailCountdown(DateTime date) {
    final remaining = date.toLocal().difference(DateTime.now());
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes.remainder(60);
    return '${hours.toString().padLeft(2, '0')}h : ${minutes.toString().padLeft(2, '0')}m';
  }

  void _scrollLatestAiContentIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final latestContext = _latestAiContentKey.currentContext;
      if (mounted && latestContext != null) {
        Scrollable.ensureVisible(latestContext, alignment: 0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Widget _askAiTab() => Column(children: [
    Expanded(child: _aiMessages.isEmpty && _pendingAiQuestion == null
        ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
            Image.asset('assets/ailogo.png', width: 34, height: 34, color: AppColors.acid),
            const SizedBox(height: 12),
            const Text('Ask Spoda AI about this match', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 7),
            const Text('Get match insights and answers in a conversation.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 12)),
            const SizedBox(height: 14),
            Wrap(spacing: 7, children: _prompts.map((p) => ActionChip(label: Text(p, style: const TextStyle(fontSize: 11)), onPressed: () => setState(() => _question.text = p), backgroundColor: AppColors.surface, side: const BorderSide(color: AppColors.border))).toList()),
            const SizedBox(height: 10),
            FutureBuilder<bool>(future: _isLoggedIn, builder: (context, snapshot) => snapshot.data == true ? const SizedBox.shrink() : OutlinedButton(onPressed: _requireLogin, child: const Text('Log in to chat', style: TextStyle(color: AppColors.acid)))),
          ])))
        : ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
            itemCount: _aiMessages.length + (_pendingAiQuestion == null ? 0 : 1),
            itemBuilder: (context, index) {
              if (index == _aiMessages.length) {
                return Column(key: _latestAiContentKey, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _aiQuestionBubble(_pendingAiQuestion!, canRetry: false),
                  _aiLoadingCard(),
                ]);
              }
              final message = _aiMessages[index];
              final answer = _formatAiAnswer(message.answer);
              final isExpanded = _expandedAiAnswers.contains(index);
              final hasMore = answer.split('\n').length > 12 || answer.length > 450;
              return Column(key: _pendingAiQuestion == null && index == _aiMessages.length - 1 ? _latestAiContentKey : null, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _aiQuestionBubble(message.question, canRetry: true),
                Row(children: [Image.asset('assets/chat-icon.png', width: 30, height: 30), const SizedBox(width: 7), const Text('Spoda AI', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14))]),
                Padding(
                  padding: const EdgeInsets.fromLTRB(25, 8, 0, 0),
                  child: isExpanded
                      ? SelectableText(answer, style: const TextStyle(fontSize: 13, height: 1.5))
                      : Text(answer, maxLines: 12, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, height: 1.5)),
                ),
                if (hasMore)
                  Padding(padding: const EdgeInsets.only(left: 25, bottom: 20), child: Align(alignment: Alignment.centerLeft, child: TextButton(
                    onPressed: () => setState(() => isExpanded ? _expandedAiAnswers.remove(index) : _expandedAiAnswers.add(index)),
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    child: Text(isExpanded ? 'Show less' : 'Read more', style: const TextStyle(color: AppColors.acid, fontSize: 12)),
                  )))
                else
                  const SizedBox(height: 20),
              ]);
            },
          )),
    _aiComposer(),
  ]);

  Widget _aiQuestionBubble(String question, {bool canRetry = false}) => Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
    ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: const BoxDecoration(color: AppColors.acid, borderRadius: BorderRadius.zero),
        child: Text(question, style: const TextStyle(color: AppColors.background, fontSize: 12, height: 1.4)),
      ),
    ),
    if (canRetry)
      Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(tooltip: 'Copy question', visualDensity: VisualDensity.compact, onPressed: () async {
          await Clipboard.setData(ClipboardData(text: question));
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Question copied')));
        }, icon: const Icon(Icons.copy, size: 17, color: AppColors.muted)),
        IconButton(tooltip: 'Resend question', visualDensity: VisualDensity.compact, onPressed: _chatSending ? null : () {
          _question.text = question;
          _submitAiQuestion();
        }, icon: const Icon(Icons.replay, size: 19, color: AppColors.muted)),
      ]),
    const SizedBox(height: 12),
  ]);

  Widget _aiLoadingCard() => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Row(
      children: [
        Image.asset('assets/chat-icon.png', width: 30, height: 30),
        const SizedBox(width: 7),
        const Expanded(
          child: Text('Spoda AI is thinking…', style: TextStyle(fontSize: 12, color: AppColors.muted)),
        ),
      ],
    ),
  );

  String _formatAiAnswer(String value) => value
      .replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '')
      .replaceAll('**', '')
      .replaceAll(RegExp(r'^\s*[-*]\s+', multiLine: true), '• ');

  Widget _aiComposer() => SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(10, 6, 10, 8), child: Row(children: [
    Expanded(child: TextField(controller: _question, minLines: 1, maxLines: 3, textInputAction: TextInputAction.send, onSubmitted: (_) => _submitAiQuestion(), style: const TextStyle(fontSize: 13), decoration: const InputDecoration(hintText: 'Ask anything about cricket...', hintStyle: TextStyle(color: AppColors.muted, fontSize: 12), filled: true, fillColor: AppColors.surface, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12), enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.border), borderRadius: BorderRadius.zero), focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.acid), borderRadius: BorderRadius.zero)))),
    const SizedBox(width: 7),
    SizedBox(width: 42, height: 42, child: IconButton.filled(onPressed: _chatSending ? null : () => _submitAiQuestion(), style: IconButton.styleFrom(backgroundColor: AppColors.acid, foregroundColor: AppColors.background, shape: const RoundedRectangleBorder(), padding: EdgeInsets.zero), icon: _chatSending ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.background)) : const Icon(Icons.send, size: 19))),
  ])));

  Widget _askAiSection() => Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
        decoration: BoxDecoration(color: const Color(0xFF080808), border: Border.all(color: AppColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [Icon(Icons.auto_awesome, size: 15, color: AppColors.acid), SizedBox(width: 6), Text('Ask AI about this Match', style: TextStyle(color: AppColors.acid, fontSize: 13, fontWeight: FontWeight.w700))]),
          const SizedBox(height: 14),
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: _prompts.map((prompt) => Padding(padding: const EdgeInsets.only(right: 6), child: ActionChip(
            label: Text(prompt, style: const TextStyle(fontSize: 9, color: Colors.white)),
            onPressed: () => setState(() => _question.text = prompt),
            backgroundColor: AppColors.surface,
            side: const BorderSide(color: AppColors.border),
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 2),
          ))).toList())),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: _question, textInputAction: TextInputAction.send, onSubmitted: (_) => _submitAiQuestion(openAiTab: true), style: const TextStyle(fontSize: 12), decoration: const InputDecoration(hintText: 'Ask anything about this match...', hintStyle: TextStyle(color: AppColors.muted, fontSize: 11), filled: true, fillColor: AppColors.surface, contentPadding: EdgeInsets.symmetric(horizontal: 9, vertical: 10), enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.border), borderRadius: BorderRadius.zero), focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.acid), borderRadius: BorderRadius.zero)))),
            const SizedBox(width: 6),
            SizedBox(height: 38, width: 38, child: IconButton.filled(onPressed: _chatSending ? null : () => _submitAiQuestion(openAiTab: true), style: IconButton.styleFrom(backgroundColor: AppColors.acid, foregroundColor: AppColors.background, shape: const RoundedRectangleBorder(), padding: EdgeInsets.zero), icon: const Icon(Icons.send, size: 18))),
          ]),
        ]),
        );

  Widget _askAiStatus(String message, {bool loading = false}) => ListView(children: [
    SizedBox(
      height: 220,
      child: Center(child: loading
          ? const CircularProgressIndicator(color: AppColors.acid)
          : Text(message, style: const TextStyle(color: AppColors.muted))),
    ),
    _askAiSection(),
  ]);
}

class _SideMenu extends StatefulWidget {
  const _SideMenu({this.onMatches});
  final VoidCallback? onMatches;

  @override
  State<_SideMenu> createState() => _SideMenuState();
}

class _SideMenuState extends State<_SideMenu> {
  late final Future<String?> _tokenFuture = AuthService.instance.accessToken();
  late final Future<int> _passesFuture = AuthService.instance.remainingPasses();

  void _open(BuildContext context, String title) {
    Navigator.of(context).pop();
    final page = switch (title) {
      'Terms of Use' => LegalDocumentPage(title: title, assetPath: 'assets/legal/terms_of_use.txt'),
      'Privacy Policy' => LegalDocumentPage(title: title, assetPath: 'assets/legal/privacy_policy.txt'),
      'Help & Support' => const HelpSupportPage(),
      'Pass History' => const MatchPassesPage(),
      'About Spoda' => const AboutSpodaPage(),
      _ => SimplePage(title: title),
    };
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _choosePassLocation() async {
    const countries = [
      'INDIA', 'AUSTRIA', 'BELGIUM', 'CROATIA', 'CYPRUS', 'ESTONIA', 'FINLAND', 'FRANCE', 'GERMANY', 'GREECE',
      'IRELAND', 'ITALY', 'LATVIA', 'LITHUANIA', 'LUXEMBOURG', 'MALTA', 'NETHERLANDS', 'PORTUGAL', 'SLOVAKIA',
      'SLOVENIA', 'SPAIN', 'ENGLAND', 'SCOTLAND', 'WALES', 'NORTHERN IRELAND', 'QATAR', 'UAE', 'AUSTRALIA',
      'NEW ZEALAND', 'UNITED STATES', 'CANADA', 'KENYA', 'SOUTH AFRICA', 'NIGERIA', 'SRILANKA', 'MALAYSIA',
      'SINGAPORE', 'BANGLADESH', 'CHINA', 'THAILAND',
    ];
    const states = <String, String>{
      'ANDHRA PRADESH': 'Andhra Pradesh', 'ARUNACHAL PRADESH': 'Arunachal Pradesh', 'ASSAM': 'Assam',
      'BIHAR': 'Bihar', 'CHHATTISGARH': 'Chhattisgarh', 'GOA': 'Goa', 'GUJARAT': 'Gujarat', 'HARYANA': 'Haryana',
      'HIMACHAL PRADESH': 'Himachal Pradesh', 'JHARKHAND': 'Jharkhand', 'KARNATAKA': 'Karnataka', 'KERALA': 'Kerala',
      'MADHYA PRADESH': 'Madhya Pradesh', 'MAHARASHTRA': 'Maharashtra', 'MANIPUR': 'Manipur', 'MEGHALAYA': 'Meghalaya',
      'MIZORAM': 'Mizoram', 'NAGALAND': 'Nagaland', 'ODISHA': 'Odisha', 'PUNJAB': 'Punjab', 'RAJASTHAN': 'Rajasthan',
      'SIKKIM': 'Sikkim', 'TAMIL NADU': 'Tamil Nadu', 'TELANGANA': 'Telangana', 'TRIPURA': 'Tripura',
      'UTTAR PRADESH': 'Uttar Pradesh', 'UTTARAKHAND': 'Uttarakhand', 'WEST BENGAL': 'West Bengal',
      'ANDAMAN AND NICOBAR ISLANDS': 'Andaman and Nicobar Islands', 'CHANDIGARH': 'Chandigarh', 'DELHI': 'Delhi',
      'JAMMU AND KASHMIR': 'Jammu and Kashmir', 'LADAKH': 'Ladakh', 'LAKSHADWEEP': 'Lakshadweep', 'PUDUCHERRY': 'Puducherry',
    };
    String? country;
    String? state;
    final selection = await showDialog<(String, String?)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Choose your location'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Country', style: TextStyle(color: AppColors.muted, fontSize: 12)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: country,
              dropdownColor: AppColors.surface,
              decoration: _locationDropdownDecoration(),
              hint: const Text('Select country'),
              items: countries.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
              onChanged: (value) => setDialogState(() { country = value; state = null; }),
            ),
            const SizedBox(height: 16),
            if (country == 'INDIA') ...[
              const Text('State', style: TextStyle(color: AppColors.muted, fontSize: 12)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: state,
                dropdownColor: AppColors.surface,
                decoration: _locationDropdownDecoration(),
                hint: const Text('Select state'),
                items: states.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                onChanged: (value) => setDialogState(() => state = value),
              ),
            ],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel', style: TextStyle(color: AppColors.muted))),
            ElevatedButton(
              onPressed: country == null || (country == 'INDIA' && state == null)
                  ? null
                  : () => Navigator.of(dialogContext).pop((country!, country == 'INDIA' ? state : null)),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.acid, foregroundColor: AppColors.background, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero)),
              child: const Text('View Prices'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || selection == null) return;
    final navigator = Navigator.of(context);
    navigator.pop();
    await navigator.push(MaterialPageRoute(builder: (_) => PricingPlansPage(country: selection.$1, state: selection.$2)));
  }
  @override
  Widget build(BuildContext context) {
    final profile = AuthService.instance.profile;
    final name = profile?['fullName']?.toString();
    return Material(color: AppColors.background, child: SafeArea(child: Column(children: [
      Align(alignment: Alignment.centerRight, child: IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close))),
      ListTile(leading: const CircleAvatar(backgroundColor: AppColors.surface, child: Text('SP')), title: Text(name?.isNotEmpty == true ? name! : 'Guest'), subtitle: Text(profile?['email']?.toString() ?? 'View Profile  ›', style: const TextStyle(color: AppColors.muted)), onTap: () => _open(context, 'Profile')),
      const Divider(color: AppColors.border),
      ListTile(leading: const Icon(Icons.emoji_events_outlined, size: 20), title: const Text('Matches', style: TextStyle(fontSize: 14)), trailing: const Icon(Icons.chevron_right, size: 20), onTap: widget.onMatches),
      const Padding(padding: EdgeInsets.fromLTRB(18, 12, 18, 4), child: Align(alignment: Alignment.centerLeft, child: Text('Help & Information', style: TextStyle(color: AppColors.muted, fontSize: 11)))),
      _menuItem(context, Icons.headset_mic_outlined, 'Help & Support'), _menuItem(context, Icons.info_outline, 'About Spoda'), _menuItem(context, Icons.settings_outlined, 'Settings'),
      const Divider(color: AppColors.border, indent: 16, endIndent: 16),
      const Padding(padding: EdgeInsets.fromLTRB(18, 12, 18, 4), child: Align(alignment: Alignment.centerLeft, child: Text('Legal', style: TextStyle(color: AppColors.muted, fontSize: 11)))),
      _menuItem(context, Icons.article_outlined, 'Terms of Use'), _menuItem(context, Icons.lock_outline, 'Privacy Policy'),
      const Spacer(),
      FutureBuilder<String?>(
        future: _tokenFuture,
        builder: (context, tokenSnapshot) {
          final loggedIn = (tokenSnapshot.data ?? '').isNotEmpty;
          if (tokenSnapshot.connectionState == ConnectionState.waiting) return const SizedBox.shrink();
          if (loggedIn) {
            return ListTile(
              leading: const Icon(Icons.logout, color: AppColors.muted),
              title: const Text('Logout'),
              onTap: () async {
                await AuthService.instance.logout();
                if (context.mounted) Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LandingPage()), (_) => false);
              },
            );
          }
          return ListTile(
            leading: const Icon(Icons.login, color: AppColors.muted),
            title: const Text('Login'),
            onTap: () {
              final navigator = Navigator.of(context);
              navigator.pop();
              navigator.push(MaterialPageRoute(builder: (_) => const LoginPage()));
            },
          );
        },
      ),
      FutureBuilder<String?>(
        future: _tokenFuture,
        builder: (context, tokenSnapshot) {
          final loggedIn = (tokenSnapshot.data ?? '').isNotEmpty;
          return FutureBuilder<int>(
            future: _passesFuture,
            builder: (context, passSnapshot) {
              final count = loggedIn && passSnapshot.hasData ? passSnapshot.data! : 0;
              final loading = loggedIn && passSnapshot.connectionState == ConnectionState.waiting;
              return Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Image.asset('assets/ticket-menu.png', width: 36, height: 36, fit: BoxFit.contain),
                      const SizedBox(width: 12),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(loading ? '—' : '$count', style: const TextStyle(fontSize: 26, height: 1, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        const Text('Passes Remaining', style: TextStyle(color: AppColors.muted, fontSize: 11)),
                      ]),
                    ]),
                    if (loggedIn)
                      GestureDetector(
                        onTap: () => _open(context, 'Pass History'),
                        child: const Padding(padding: EdgeInsets.only(top: 10), child: Text('View Pass History  ›', style: TextStyle(color: AppColors.muted, fontSize: 11))),
                      ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,  
                      height: 42,
                      child: ElevatedButton.icon(
                        onPressed: _choosePassLocation,
                        label: const Text('Buy More passes', style: TextStyle(color: AppColors.background, fontWeight: FontWeight.w700)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.acid,
                          foregroundColor: AppColors.background,
                          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    ])));
  }

  Widget _menuItem(BuildContext context, IconData icon, String title) => ListTile(
        dense: true,
        leading: Icon(icon, size: 20),
        title: Text(title, style: const TextStyle(fontSize: 14)),
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: () => title == 'Settings'
            ? Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsPage()))
            : _open(context, title),
      );
}

InputDecoration _locationDropdownDecoration() => const InputDecoration(
      filled: true,
      fillColor: AppColors.background,
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.border), borderRadius: BorderRadius.zero),
      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.acid), borderRadius: BorderRadius.zero),
    );

class _WicketPhase {
  const _WicketPhase(this.name, this.firstInnings, this.secondInnings);
  final String name;
  final num firstInnings;
  final num secondInnings;
}

class _RunsPhase {
  const _RunsPhase(this.name, this.firstInnings, this.secondInnings);
  final String name;
  final num firstInnings;
  final num secondInnings;
}

class _BoundaryValues {
  const _BoundaryValues(this.innings, this.fours, this.sixes);
  final String innings;
  final num fours;
  final num sixes;
}

class _TeamSeries {
  const _TeamSeries(this.name, this.values);
  final String name;
  final List<num> values;
}

class _TeamBoundary {
  const _TeamBoundary(this.name, this.fours, this.sixes);
  final String name;
  final num fours, sixes;
}

class _TeamLineChart extends StatelessWidget {
  const _TeamLineChart({required this.teams, required this.metric, required this.xAxis});
  final List<_TeamSeries> teams;
  final String metric;
  final String xAxis;
  @override
  Widget build(BuildContext context) {
    if (teams.isEmpty || teams.every((team) => team.values.isEmpty)) return const SizedBox(height: 220, child: Center(child: Text('No team trend data available.', style: TextStyle(color: AppColors.muted, fontSize: 11))));
    final colors = [const Color(0xFF5B8FF9), const Color(0xFF34D399)];
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [for (var i = 0; i < teams.length; i++) Padding(padding: const EdgeInsets.symmetric(horizontal: 5), child: _ChartLegend(color: colors[i % colors.length], label: teams[i].name))]),
      const SizedBox(height: 8),
      Row(children: [
        RotatedBox(quarterTurns: 3, child: Text(metric, style: const TextStyle(fontSize: 9, color: AppColors.muted))),
        Expanded(child: SizedBox(height: 255, child: CustomPaint(painter: _TeamLinePainter(teams, metric, colors)))),
      ]),
      Text(xAxis, style: const TextStyle(fontSize: 10, color: AppColors.muted)),
    ]);
  }
}

class _TeamLinePainter extends CustomPainter {
  _TeamLinePainter(this.teams, this.metric, this.colors);
  final List<_TeamSeries> teams;
  final String metric;
  final List<Color> colors;
  @override
  void paint(Canvas canvas, Size size) {
    const left = 30.0, right = 6.0, top = 10.0, bottom = 28.0;
    final values = teams.expand((e) => e.values).toList();
    if (values.isEmpty) return;
    final max = (values.fold<num>(0, (a, b) => a > b ? a : b) * 1.15).clamp(1, double.infinity).toDouble();
    final w = size.width - left - right, h = size.height - top - bottom;
    final grid = Paint()..color = AppColors.border..strokeWidth = .6;
    for (var tick = 0; tick <= 4; tick++) {
      final y = top + h * (1 - tick / 4);
      canvas.drawLine(Offset(left, y), Offset(size.width - right, y), grid);
      final tp = TextPainter(text: TextSpan(text: (max * tick / 4).toStringAsFixed(0), style: const TextStyle(color: AppColors.muted, fontSize: 8)), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(left - tp.width - 4, y - tp.height / 2));
    }
    final count = teams.fold<int>(0, (n, team) => n > team.values.length ? n : team.values.length);
    for (var i = 0; i < count; i++) {
      final x = left + (count <= 1 ? w / 2 : w * i / (count - 1));
      final label = TextPainter(text: TextSpan(text: 'M${i + 1}', style: const TextStyle(color: AppColors.muted, fontSize: 8)), textDirection: TextDirection.ltr)..layout();
      label.paint(canvas, Offset(x - label.width / 2, size.height - 14));
    }
    for (var ti = 0; ti < teams.length; ti++) {
      final points = <Offset>[];
      for (var i = 0; i < teams[ti].values.length; i++) {
        final x = left + (count <= 1 ? w / 2 : w * i / (count - 1));
        points.add(Offset(x, top + h * (1 - teams[ti].values[i].toDouble() / max)));
      }
      final path = Path();
      for (var i = 0; i < points.length; i++) { if (i == 0) {
        path.moveTo(points[i].dx, points[i].dy);
      } else {
        path.lineTo(points[i].dx, points[i].dy);
      } }
      canvas.drawPath(path, Paint()..color = colors[ti % colors.length]..style = PaintingStyle.stroke..strokeWidth = 2.2);
      for (final p in points) { canvas.drawCircle(p, 2.2, Paint()..color = colors[ti % colors.length]); }
    }
  }
  @override
  bool shouldRepaint(covariant _TeamLinePainter old) => old.teams != teams || old.metric != metric;
}

class _TeamBoundaryChart extends StatelessWidget {
  const _TeamBoundaryChart({required this.teams});
  final List<_TeamBoundary> teams;
  @override
  Widget build(BuildContext context) {
    if (teams.isEmpty) return const SizedBox(height: 120, child: Center(child: Text('No boundary percentage data available.', style: TextStyle(color: AppColors.muted, fontSize: 11))));
    return Row(children: [for (final team in teams) Expanded(child: Column(children: [Text(team.name, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)), const SizedBox(height: 6), SizedBox(width: 126, height: 126, child: Stack(alignment: Alignment.center, children: [CustomPaint(size: const Size(126, 126), painter: _BoundaryDonutPainter(team.fours, team.sixes)), Column(mainAxisSize: MainAxisSize.min, children: [const Text('Total', style: TextStyle(fontSize: 9)), const Text('Percentage', style: TextStyle(fontSize: 9)), Text('${(team.fours + team.sixes).toStringAsFixed(2)}%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))])])), const SizedBox(height: 6), _BoundaryLegend(color: _BoundaryDonutPainter.foursColor, label: 'Fours ${team.fours}'), _BoundaryLegend(color: _BoundaryDonutPainter.sixesColor, label: 'Sixes ${team.sixes}')]))]);
  }
}

class _BoundaryLegend extends StatelessWidget {
  const _BoundaryLegend({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 4), Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 9))),
  ]);
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 4), Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 9)),
  ]);
}

class _WicketsPainter extends CustomPainter {
  _WicketsPainter(this.rows);
  final List<_WicketPhase> rows;
  static const _first = Color(0xFF5B8FF9);
  static const _second = Color(0xFF34D399);
  @override
  void paint(Canvas canvas, Size size) {
    const left = 28.0, right = 5.0, top = 8.0, bottom = 8.0;
    final chartWidth = size.width - left - right;
    final chartHeight = size.height - top - bottom;
    final maxValue = rows.fold<num>(1, (max, row) => [max, row.firstInnings, row.secondInnings].reduce((a, b) => a > b ? a : b));
    final maxAxis = ((maxValue / 2).ceil() * 2).clamp(2, 20).toInt();
    final grid = Paint()..color = AppColors.border..strokeWidth = .7;
    final textStyle = const TextStyle(color: AppColors.muted, fontSize: 9);
    for (var tick = 0; tick <= maxAxis; tick += maxAxis <= 10 ? 1 : 2) {
      final y = top + chartHeight - chartHeight * tick / maxAxis;
      canvas.drawLine(Offset(left, y), Offset(size.width - right, y), grid);
      final label = TextPainter(text: TextSpan(text: '$tick', style: textStyle), textDirection: TextDirection.ltr)..layout();
      label.paint(canvas, Offset(left - label.width - 5, y - label.height / 2));
    }
    final groupWidth = chartWidth / rows.length;
    final barWidth = (groupWidth * .28).clamp(5, 16).toDouble();
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final center = left + groupWidth * (i + .5);
      for (final entry in [(row.firstInnings, _first, center - barWidth - 1), (row.secondInnings, _second, center + 1)]) {
        final value = entry.$1.toDouble();
        final barHeight = chartHeight * value / maxAxis;
        final rect = Rect.fromLTWH(entry.$3, top + chartHeight - barHeight, barWidth, barHeight);
        canvas.drawRect(rect, Paint()..color = entry.$2);
        final label = TextPainter(text: TextSpan(text: value.toStringAsFixed(value % 1 == 0 ? 0 : 1), style: const TextStyle(color: Colors.white, fontSize: 8)), textDirection: TextDirection.ltr)..layout();
        label.paint(canvas, Offset(rect.center.dx - label.width / 2, rect.top - label.height - 2));
      }
    }
  }
  @override
  bool shouldRepaint(covariant _WicketsPainter oldDelegate) => oldDelegate.rows != rows;
}

class _RunsPhasePainter extends CustomPainter {
  _RunsPhasePainter(this.rows);
  final List<_RunsPhase> rows;
  static const _first = Color(0xFF5B8FF9);
  static const _second = Color(0xFF34D399);

  double _rate(_RunsPhase row, num value) => value.toDouble() / (row.name.toLowerCase().contains('20 overs') ? 20 : 10);
  String _valueLabel(num value) => value.toStringAsFixed(value % 1 == 0 ? 0 : 2);
  String _phaseLabel(String name) => switch (name.toLowerCase()) {
    'powerplay' || 'power play' => 'Powerplay',
    'middle' => 'Middle',
    'death' => 'Death',
    'total' || 'in 20 overs' => 'Total',
    _ => name,
  };
  String _overs(String name) => switch (name.toLowerCase()) {
    'powerplay' || 'power play' => '(0-6 Overs)',
    'middle' => '(7-15 Overs)',
    'death' => '(15-20 Overs)',
    'total' || 'in 20 overs' => '(In 20 Overs)',
    _ => '',
  };

  @override
  void paint(Canvas canvas, Size size) {
    const left = 30.0, right = 8.0, top = 18.0, bottom = 42.0;
    final width = size.width - left - right;
    final height = size.height - top - bottom;
    final highest = rows.fold<double>(1, (max, row) => [max, _rate(row, row.firstInnings), _rate(row, row.secondInnings)].reduce((a, b) => a > b ? a : b));
    final maxAxis = (((highest.ceil() + 1) / 2).ceil() * 2).clamp(2, 20).toInt();
    final grid = Paint()..color = AppColors.border..strokeWidth = .7;
    const axisText = TextStyle(color: AppColors.muted, fontSize: 9);
    for (var tick = 0; tick <= maxAxis; tick++) {
      final y = top + height - height * tick / maxAxis;
      canvas.drawLine(Offset(left, y), Offset(size.width - right, y), grid);
      final label = TextPainter(text: TextSpan(text: '$tick', style: axisText), textDirection: TextDirection.ltr)..layout();
      label.paint(canvas, Offset(left - label.width - 6, y - label.height / 2));
    }
    canvas.drawLine(Offset(left, top), Offset(left, top + height), Paint()..color = AppColors.border..strokeWidth = 1);
    canvas.drawLine(Offset(left, top + height), Offset(size.width - right, top + height), Paint()..color = AppColors.border..strokeWidth = 1);
    final axis = TextPainter(text: const TextSpan(text: 'Runs', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600)), textDirection: TextDirection.ltr)..layout();
    canvas.save();
    canvas.translate(8, top + height / 2 + axis.width / 2);
    canvas.rotate(-math.pi / 2);
    axis.paint(canvas, Offset.zero);
    canvas.restore();

    List<Offset> pointsFor(bool first) => [
      for (var i = 0; i < rows.length; i++) Offset(
        left + (rows.length == 1 ? width / 2 : width * i / (rows.length - 1)),
        top + height - height * (_rate(rows[i], first ? rows[i].firstInnings : rows[i].secondInnings).clamp(0, maxAxis).toDouble()) / maxAxis,
      ),
    ];
    void drawSeries(bool isFirst, Color color) {
      final points = pointsFor(isFirst);
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (var i = 0; i < points.length - 1; i++) {
        final midpoint = (points[i].dx + points[i + 1].dx) / 2;
        path.cubicTo(midpoint, points[i].dy, midpoint, points[i + 1].dy, points[i + 1].dx, points[i + 1].dy);
      }
      canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2..strokeCap = StrokeCap.round);
      for (var i = 0; i < points.length; i++) {
        final point = points[i];
        canvas.drawCircle(point, 2.5, Paint()..color = color);
        final raw = isFirst ? rows[i].firstInnings : rows[i].secondInnings;
        final label = TextPainter(text: TextSpan(text: _valueLabel(raw), style: const TextStyle(color: Colors.white, fontSize: 8)), textDirection: TextDirection.ltr)..layout();
        final offset = Offset(point.dx - label.width / 2, point.dy + (isFirst ? -label.height - 5 : 5));
        label.paint(canvas, offset);
      }
    }
    drawSeries(true, _first);
    drawSeries(false, _second);
    for (var i = 0; i < rows.length; i++) {
      final x = left + (rows.length == 1 ? width / 2 : width * i / (rows.length - 1));
      final title = TextPainter(text: TextSpan(text: _phaseLabel(rows[i].name), style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600)), textDirection: TextDirection.ltr, textAlign: TextAlign.center)..layout(maxWidth: width / rows.length);
      title.paint(canvas, Offset(x - title.width / 2, top + height + 7));
      final overs = TextPainter(text: TextSpan(text: _overs(rows[i].name), style: axisText), textDirection: TextDirection.ltr, textAlign: TextAlign.center)..layout(maxWidth: width / rows.length);
      overs.paint(canvas, Offset(x - overs.width / 2, top + height + 20));
    }
  }

  @override
  bool shouldRepaint(covariant _RunsPhasePainter oldDelegate) => oldDelegate.rows != rows;
}

class _EconomyPhasePainter extends CustomPainter {
  _EconomyPhasePainter(this.rows);
  final List<_RunsPhase> rows;
  static const _first = Color(0xFF5B8FF9);
  static const _second = Color(0xFF34D399);
  static const _axisText = TextStyle(color: AppColors.muted, fontSize: 9);

  String _phaseLabel(String name) => switch (name.toLowerCase()) {
    'powerplay' || 'power play' => 'Powerplay',
    'middle' => 'Middle',
    'death' => 'Death',
    _ => name,
  };
  String _overs(String name) => switch (name.toLowerCase()) {
    'powerplay' || 'power play' => '(0-6 Overs)',
    'middle' => '(7-15 Overs)',
    'death' => '(15-20 Overs)',
    _ => '',
  };

  @override
  void paint(Canvas canvas, Size size) {
    const left = 28.0, right = 6.0, top = 14.0, bottom = 39.0;
    const maxAxis = 10.0;
    final width = size.width - left - right;
    final height = size.height - top - bottom;
    final grid = Paint()..color = AppColors.border..strokeWidth = .7;
    for (var tick = 0; tick <= maxAxis; tick++) {
      final y = top + height - height * tick / maxAxis;
      canvas.drawLine(Offset(left, y), Offset(size.width - right, y), grid);
      final label = TextPainter(text: TextSpan(text: '$tick', style: _axisText), textDirection: TextDirection.ltr)..layout();
      label.paint(canvas, Offset(left - label.width - 5, y - label.height / 2));
    }
    canvas.drawLine(Offset(left, top + height), Offset(size.width - right, top + height), Paint()..color = AppColors.border..strokeWidth = 1);
    final axis = TextPainter(text: const TextSpan(text: 'Runs', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600)), textDirection: TextDirection.ltr)..layout();
    canvas.save();
    canvas.translate(7, top + height / 2 + axis.width / 2);
    canvas.rotate(-math.pi / 2);
    axis.paint(canvas, Offset.zero);
    canvas.restore();

    final groupWidth = width / rows.length;
    final barWidth = (groupWidth * .17).clamp(5, 14).toDouble();
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final center = left + groupWidth * (i + .5);
      for (final entry in [(row.firstInnings, _first, center - barWidth - 1), (row.secondInnings, _second, center + 1)]) {
        final value = entry.$1.toDouble();
        final barHeight = height * value.clamp(0, maxAxis).toDouble() / maxAxis;
        final rect = Rect.fromLTWH(entry.$3, top + height - barHeight, barWidth, barHeight);
        canvas.drawRect(rect, Paint()..color = entry.$2);
        final label = TextPainter(text: TextSpan(text: value.toStringAsFixed(2), style: const TextStyle(color: Colors.white, fontSize: 7)), textDirection: TextDirection.ltr)..layout();
        label.paint(canvas, Offset(rect.center.dx - label.width / 2, rect.top - label.height - 2));
      }
      final title = TextPainter(text: TextSpan(text: _phaseLabel(row.name), style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600)), textDirection: TextDirection.ltr, textAlign: TextAlign.center)..layout(maxWidth: groupWidth);
      title.paint(canvas, Offset(center - title.width / 2, top + height + 7));
      final overs = TextPainter(text: TextSpan(text: _overs(row.name), style: _axisText), textDirection: TextDirection.ltr, textAlign: TextAlign.center)..layout(maxWidth: groupWidth);
      overs.paint(canvas, Offset(center - overs.width / 2, top + height + 20));
    }
  }

  @override
  bool shouldRepaint(covariant _EconomyPhasePainter oldDelegate) => oldDelegate.rows != rows;
}

class _BoundaryDonutPainter extends CustomPainter {
  const _BoundaryDonutPainter(this.fours, this.sixes);
  final num fours;
  final num sixes;
  static const foursColor = Color(0xFF34D399);
  static const sixesColor = Color(0xFF5B8FF9);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const strokeWidth = 26.0;
    final radius = (size.shortestSide - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final foursValue = fours.toDouble();
    final sixesValue = sixes.toDouble();
    final total = foursValue + sixesValue;
    final background = Paint()..color = AppColors.border..style = PaintingStyle.stroke..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, background);
    if (total <= 0) return;
    final foursSweep = math.pi * 2 * foursValue / total;
    final style = Paint()..style = PaintingStyle.stroke..strokeWidth = strokeWidth..strokeCap = StrokeCap.butt;
    canvas.drawArc(rect, -math.pi / 2, foursSweep, false, style..color = foursColor);
    canvas.drawArc(rect, -math.pi / 2 + foursSweep, math.pi * 2 - foursSweep, false, style..color = sixesColor);
  }

  @override
  bool shouldRepaint(covariant _BoundaryDonutPainter oldDelegate) => oldDelegate.fours != fours || oldDelegate.sixes != sixes;
}

class PricingPlansPage extends StatefulWidget {
  const PricingPlansPage({super.key, required this.country, required this.state});
  final String country;
  final String? state;
  @override
  State<PricingPlansPage> createState() => _PricingPlansPageState();
}

class _PricingPlansPageState extends State<PricingPlansPage> {
  late Future<List<Map<String, dynamic>>> _plans = AuthService.instance.pricingPlans(country: widget.country, state: widget.state);

  num _number(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _money(String currency, num value) => '$currency ${value.toStringAsFixed(value % 1 == 0 ? 0 : 2)}';

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(backgroundColor: AppColors.background, title: const Text('Pass Plans')),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _plans,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: AppColors.acid));
            if (snapshot.hasError) {
              return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(snapshot.error.toString(), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
                const SizedBox(height: 12),
                TextButton(onPressed: () => setState(() => _plans = AuthService.instance.pricingPlans(country: widget.country, state: widget.state)), child: const Text('Try again', style: TextStyle(color: AppColors.acid))),
              ])));
            }
            final plans = snapshot.data ?? const [];
            if (plans.isEmpty) return const Center(child: Text('No pass plans are available for this location.', style: TextStyle(color: AppColors.muted)));
            return ListView(padding: const EdgeInsets.all(16), children: [
              Text(widget.state == null ? widget.country : '${widget.state}, ${widget.country}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              const SizedBox(height: 12),
              ...plans.map((plan) {
                final currency = plan['currencyCode']?.toString() ?? '';
                final amount = _number(plan, 'amount');
                final tax = _number(plan, 'cgst') + _number(plan, 'sgst') + _number(plan, 'igst');
                final total = amount + tax;
                final features = plan['features'] is List ? (plan['features'] as List).map((e) => e.toString()).toList() : const <String>[];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(plan['planTitle']?.toString() ?? '${plan['numOfPasses'] ?? ''} pass pack', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text(_money(currency, total), style: const TextStyle(color: AppColors.acid, fontSize: 24, fontWeight: FontWeight.w800)),
                    Text('Includes ${_money(currency, amount)} + ${_money(currency, tax)} tax', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                    const SizedBox(height: 8),
                    Text('${plan['numOfPasses'] ?? '—'} passes · ${plan['validity'] ?? 'Validity not specified'}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                    if (features.isNotEmpty) ...[
                      const Divider(color: AppColors.border, height: 22),
                      ...features.map((feature) => Padding(padding: const EdgeInsets.only(bottom: 5), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.check, size: 15, color: AppColors.acid), const SizedBox(width: 7), Expanded(child: Text(feature, style: const TextStyle(fontSize: 12, color: AppColors.muted)))]))),
                    ],
                  ]),
                );
              }),
            ]);
          },
        ),
      );

}

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, required this.postsLoader});
  final Future<List<BlogPost>> Function(Set<int>) postsLoader;

  void _open(BuildContext context, Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final profile = AuthService.instance.profile ?? const <String, dynamic>{};
    final name = (profile['fullName'] ?? profile['full_name'] ?? profile['name'] ?? '').toString().trim();
    final email = (profile['email'] ?? '').toString().trim();
    final provider = (profile['provider'] ?? profile['authProvider'] ?? profile['auth_provider'] ?? '').toString().trim();
    final initials = (name.isNotEmpty ? name : email).split(RegExp(r'[@\s.]')).where((part) => part.isNotEmpty).take(2).map((part) => part[0].toUpperCase()).join();
    return ListView(padding: EdgeInsets.zero, children: [
      Container(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20), decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))), child: Row(children: [
        CircleAvatar(radius: 27, backgroundColor: const Color(0xFF252525), child: Text(initials.isEmpty ? 'SP' : initials, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(email.isEmpty ? (name.isEmpty ? 'Spoda User' : name) : email, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(provider.isEmpty ? (name.isEmpty ? 'Spoda account' : name) : 'Signed in with $provider', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        ])),
      ])),
      _profileSection('MY SPODA', [
        _profileRow(context, Icons.confirmation_num_outlined, 'Match Passes', () => _open(context, const MatchPassesPage())),
        _profileRow(context, Icons.receipt_long_outlined, 'Purchase History', () => _open(context, const PurchaseHistoryPage())),
        _profileRow(context, Icons.bookmark_border, 'Saved', () => _open(context, SavedBlogsPage(postsLoader: postsLoader))),
      ]),
      _profileSection('ACCOUNT & APP', [
        _profileRow(context, Icons.verified_user_outlined, 'Account & Security', () => _open(context, AccountSecurityPage(email: email))),
        _profileRow(context, Icons.notifications_none, 'Notification Settings', () => _open(context, const SettingsPage())),
        _profileRow(context, Icons.help_outline, 'How to use?', () => _open(context, const HelpSupportPage())),
      ]),
      _profileSection('Legal', [
        _profileRow(context, Icons.article_outlined, 'Term of use', () => _open(context, const LegalDocumentPage(title: 'Terms of Use', assetPath: 'assets/legal/terms_of_use.txt'))),
        _profileRow(context, Icons.lock_outline, 'Privacy Policy', () => _open(context, const LegalDocumentPage(title: 'Privacy Policy', assetPath: 'assets/legal/privacy_policy.txt'))),
      ]),
      const SizedBox(height: 16),
    ]);
  }

  Widget _profileSection(String title, List<Widget> rows) => Container(
    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 9),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(bottom: 5), child: Text(title.toUpperCase(), style: const TextStyle(color: AppColors.muted, fontSize: 10))),
      ...rows,
    ]),
  );

  Widget _profileRow(BuildContext context, IconData icon, String title, VoidCallback onTap) => ListTile(
    contentPadding: EdgeInsets.zero,
    minLeadingWidth: 24,
    leading: Icon(icon, size: 21, color: Colors.white),
    title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
    trailing: const Icon(Icons.chevron_right, size: 22),
    onTap: onTap,
    visualDensity: const VisualDensity(vertical: -1),
  );
}

class MatchPassesPage extends StatefulWidget {
  const MatchPassesPage({super.key});
  @override State<MatchPassesPage> createState() => _MatchPassesPageState();
}

class _MatchPassesPageState extends State<MatchPassesPage> {
  late Future<int> _passes = AuthService.instance.remainingPasses();
  late Future<List<Map<String, dynamic>>> _history = AuthService.instance.passHistory(isUsed: true);
  int _historyVisible = 4;
  static const _countries = ['INDIA', 'UNITED STATES', 'UNITED KINGDOM', 'AUSTRALIA', 'UAE', 'SOUTH AFRICA'];

  Future<void> _browsePlans() async {
    final country = await showDialog<String>(context: context, builder: (dialogContext) => SimpleDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Choose your country'),
      children: _countries.map((value) => SimpleDialogOption(onPressed: () => Navigator.pop(dialogContext, value), child: Text(value))).toList(),
    ));
    if (!mounted || country == null) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PricingPlansPage(country: country, state: null)));
    if (mounted) {
      setState(() {
      _passes = AuthService.instance.remainingPasses();
      _history = AuthService.instance.passHistory(isUsed: true);
    });
    }
  }

  String _historyDate(Map<String, dynamic> pass) {
    final details = pass['matchDetails'];
    final start = details is Map ? DateTime.tryParse(details['startDate']?.toString() ?? '') : null;
    final timestamp = pass['dateOfUse'] ?? pass['dateOfPurchase'];
    final epoch = timestamp is num ? timestamp.toInt() : int.tryParse(timestamp?.toString() ?? '');
    final date = start?.toLocal() ?? (epoch == null ? null : DateTime.fromMillisecondsSinceEpoch(epoch * 1000).toLocal());
    if (date == null) return 'Date unavailable';
    final now = DateTime.now();
    final day = date.year == now.year && date.month == now.month && date.day == now.day
        ? 'Today'
        : '${date.day.toString().padLeft(2, '0')} ${_month(date.month)}';
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final time = '${hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} ${date.hour >= 12 ? 'PM' : 'AM'}';
    return '$day - $time';
  }

  String _month(int value) => const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][value - 1];

  Widget _historyCard(Map<String, dynamic> pass) {
    final rawDetails = pass['matchDetails'];
    final details = rawDetails is Map ? rawDetails : const <String, dynamic>{};
    final title = (details['title'] ?? '').toString().trim();
    final teamOne = (details['teamName1'] ?? '').toString().trim();
    final teamTwo = (details['teamName2'] ?? '').toString().trim();
    final teams = teamOne.isNotEmpty && teamTwo.isNotEmpty ? '$teamOne  vs  $teamTwo' : title.isNotEmpty ? title : 'Match pass used';
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border)),
      child: Row(children: [
        const Icon(Icons.sports_cricket_outlined, size: 19, color: AppColors.acid),
        const SizedBox(width: 9),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(teams, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          Text(_historyDate(pass), style: const TextStyle(color: AppColors.muted, fontSize: 11)),
        ])),
        const SizedBox(width: 8),
        const Text('- 1 Pass', style: TextStyle(color: AppColors.red, fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Match Passes'), backgroundColor: AppColors.surface),
    body: ListView(padding: const EdgeInsets.all(18), children: [
      FutureBuilder<int>(future: _passes, builder: (context, snapshot) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.confirmation_num_outlined, color: AppColors.acid, size: 30),
          const SizedBox(height: 12),
          Text(snapshot.connectionState == ConnectionState.waiting ? '—' : '${snapshot.data ?? 0}', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800)),
          const Text('Passes remaining', style: TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: 4),
          const Text('Each premium action uses 1 pass', style: TextStyle(color: AppColors.muted, fontSize: 11)),
          if (snapshot.hasError) TextButton(onPressed: () => setState(() => _passes = AuthService.instance.remainingPasses()), child: const Text('Retry')),
          const SizedBox(height: 14),
          SizedBox(width: double.infinity, child: ElevatedButton.icon(
            onPressed: _browsePlans,
            icon: const Icon(Icons.shopping_cart_outlined, size: 17),
            label: const Text('Buy More Passes', style: TextStyle(fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.acid, foregroundColor: Colors.black, shape: const RoundedRectangleBorder()),
          )),
        ]),
      )),
      const SizedBox(height: 26),
      const Padding(padding: EdgeInsets.only(bottom: 10), child: Text('USAGE HISTORY', style: TextStyle(color: AppColors.muted, fontSize: 10))),
      FutureBuilder<List<Map<String, dynamic>>>(future: _history, builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Padding(padding: EdgeInsets.all(22), child: Center(child: CircularProgressIndicator(color: AppColors.acid)));
        if (snapshot.hasError) {
          return Column(children: [
          Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text(snapshot.error.toString(), style: const TextStyle(color: AppColors.muted, fontSize: 12))),
          TextButton(onPressed: () => setState(() => _history = AuthService.instance.passHistory(isUsed: true)), child: const Text('Try again')),
        ]);
        }
        final rows = (snapshot.data ?? const <Map<String, dynamic>>[]).where((pass) => pass['isUsed'] == true || pass['isUsed'].toString().toLowerCase() == 'true').toList();
        if (rows.isEmpty) return const Padding(padding: EdgeInsets.symmetric(vertical: 18), child: Center(child: Text('No pass usage yet.', style: TextStyle(color: AppColors.muted, fontSize: 12))));
        final shown = rows.take(_historyVisible).toList();
        return Column(children: [
          ...shown.map(_historyCard),
          if (rows.length > _historyVisible)
            SizedBox(width: double.infinity, child: OutlinedButton.icon(
              onPressed: () => setState(() => _historyVisible += 4),
              icon: const Icon(Icons.expand_more, color: AppColors.acid),
              label: const Text('View More', style: TextStyle(color: AppColors.acid)),
            )),
        ]);
      }),
    ]),
  );
}

Object? _paymentValue(Map<String, dynamic> payment, List<String> keys) {
  for (final key in keys) {
    if (payment[key] != null && payment[key].toString().isNotEmpty) return payment[key];
  }
  final normalized = {for (final entry in payment.entries) entry.key.toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ''): entry.value};
  for (final key in keys) {
    final value = normalized[key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')];
    if (value != null && value.toString().isNotEmpty) return value;
  }
  return null;
}

String _paymentTitle(Map<String, dynamic> payment) {
  final title = _paymentValue(payment, ['planTitle', 'productName', 'product', 'description', 'name'])?.toString().trim() ?? '';
  if (title.isNotEmpty) return title;
  final quantity = _paymentValue(payment, ['numOfPasses', 'passCount', 'quantity', 'passes']);
  return quantity == null ? 'Match Passes' : '$quantity Passes';
}

String _paymentAmount(Map<String, dynamic> payment) {
  final amount = _paymentValue(payment, ['amountPaid', 'amount', 'totalAmount', 'total', 'paidAmount', 'price']);
  if (amount == null) return '—';
  final currencyRaw = (_paymentValue(payment, ['currencySymbol', 'currencyCode', 'currency']) ?? 'INR').toString();
  final symbol = switch (currencyRaw.toUpperCase()) {
    'INR' => '₹', 'USD' => r'$', 'GBP' => '£', 'EUR' => '€', _ => currencyRaw,
  };
  return '$symbol$amount';
}

DateTime? _paymentDate(Map<String, dynamic> payment) {
  final raw = _paymentValue(payment, ['date', 'createdAt', 'createdOn', 'paidAt', 'purchasedAt', 'dateOfPurchase', 'timestamp']);
  if (raw is num) return DateTime.fromMillisecondsSinceEpoch(raw > 9999999999 ? raw.toInt() : raw.toInt() * 1000).toLocal();
  final text = raw?.toString();
  if (text == null || text.isEmpty) return null;
  final numeric = int.tryParse(text);
  if (numeric != null) return DateTime.fromMillisecondsSinceEpoch(numeric > 9999999999 ? numeric : numeric * 1000).toLocal();
  return DateTime.tryParse(text)?.toLocal();
}

String _paymentDateLabel(Map<String, dynamic> payment) {
  final date = _paymentDate(payment);
  if (date == null) return 'Date unavailable';
  final now = DateTime.now();
  final label = date.year == now.year && date.month == now.month && date.day == now.day
      ? 'Today'
      : '${date.day.toString().padLeft(2, '0')} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][date.month - 1]}';
  final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
  return '$label · ${hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} ${date.hour >= 12 ? 'PM' : 'AM'}';
}

String _paymentStatus(Map<String, dynamic> payment) => (_paymentValue(payment, ['status', 'paymentStatus', 'orderStatus', 'transactionStatus']) ?? 'Completed').toString();
bool _paymentCompleted(Map<String, dynamic> payment) => _paymentStatus(payment).toLowerCase().contains(RegExp(r'complete|paid|success'));

class PurchaseHistoryPage extends StatefulWidget {
  const PurchaseHistoryPage({super.key});
  @override State<PurchaseHistoryPage> createState() => _PurchaseHistoryPageState();
}

class _PurchaseHistoryPageState extends State<PurchaseHistoryPage> {
  late Future<List<Map<String, dynamic>>> _payments = AuthService.instance.paymentHistory();
  int _visible = 6;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Purchase History'), backgroundColor: AppColors.surface),
    body: FutureBuilder<List<Map<String, dynamic>>>(future: _payments, builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: AppColors.acid));
      if (snapshot.hasError) {
        return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(snapshot.error.toString(), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
        const SizedBox(height: 12),
        TextButton(onPressed: () => setState(() => _payments = AuthService.instance.paymentHistory()), child: const Text('Try again')),
      ])));
      }
      final payments = snapshot.data ?? const <Map<String, dynamic>>[];
      if (payments.isEmpty) {
        return const Center(child: Padding(padding: EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.receipt_long_outlined, size: 42, color: AppColors.muted),
        SizedBox(height: 12),
        Text('No purchases to show yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        SizedBox(height: 6),
        Text('Your match pass purchases will appear here.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 12)),
      ])));
      }
      final visible = payments.take(_visible).toList();
      return ListView(padding: const EdgeInsets.all(16), children: [
        const Padding(padding: EdgeInsets.only(bottom: 12), child: Text('PURCHASE HISTORY', style: TextStyle(color: AppColors.muted, fontSize: 10))),
        ...visible.map((payment) => _paymentCard(context, payment)),
        if (payments.length > _visible) SizedBox(width: double.infinity, child: OutlinedButton.icon(
          onPressed: () => setState(() => _visible += 6),
          icon: const Icon(Icons.expand_more, color: AppColors.acid),
          label: const Text('View More', style: TextStyle(color: AppColors.acid)),
        )),
      ]);

    }),
  );

  Widget _paymentCard(BuildContext context, Map<String, dynamic> payment) => InkWell(
    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PurchaseDetailsPage(payment: payment))),
    child: Container(margin: const EdgeInsets.only(bottom: 9), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border)), child: Row(children: [
      const Icon(Icons.confirmation_num_outlined, size: 20, color: Colors.white),
      const SizedBox(width: 9),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_paymentTitle(payment), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 5),
        Text(_paymentDateLabel(payment), style: const TextStyle(color: AppColors.muted, fontSize: 10)),
      ])),
      const SizedBox(width: 8),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(_paymentAmount(payment), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 5),
        Text(_paymentStatus(payment), style: TextStyle(color: _paymentCompleted(payment) ? const Color(0xFF68C45A) : AppColors.muted, fontSize: 10)),
      ]),
      const SizedBox(width: 3),
      const Icon(Icons.chevron_right, size: 20),
    ])),
  );
}

class PurchaseDetailsPage extends StatelessWidget {
  const PurchaseDetailsPage({super.key, required this.payment});
  final Map<String, dynamic> payment;

  Widget _detail(String label, Object? value) => Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(children: [
    Expanded(child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12))),
    const SizedBox(width: 8),
    Flexible(child: Text(value == null || value.toString().isEmpty ? '—' : value.toString(), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12))),
  ]));

  @override
  Widget build(BuildContext context) {
    final status = _paymentStatus(payment);
    final orderId = _paymentValue(payment, ['orderId', 'id', 'order_id']);
    final quantity = _paymentValue(payment, ['numOfPasses', 'passCount', 'quantity', 'passes']);
    final paymentMethod = _paymentValue(payment, ['paymentMethod', 'method', 'provider', 'paymentType']);
    final paymentId = _paymentValue(payment, ['paymentId', 'transactionId', 'payment_id', 'transaction_id']);
    return Scaffold(
      appBar: AppBar(title: const Text('Purchase Details'), backgroundColor: AppColors.surface),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(border: Border.all(color: AppColors.border)), child: Column(children: [
          const SizedBox(height: 4),
          Container(width: 56, height: 56, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.acid)), child: const Icon(Icons.confirmation_num_outlined, color: AppColors.acid, size: 28)),
          const SizedBox(height: 12),
          Text(_paymentTitle(payment), textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(status, style: TextStyle(color: _paymentCompleted(payment) ? const Color(0xFF68C45A) : AppColors.muted, fontSize: 12)),
          const Divider(color: AppColors.border, height: 30),
          _detail('Order Id', orderId),
          _detail('Date', _paymentDateLabel(payment)),
          _detail('Quantity', quantity == null ? _paymentTitle(payment) : '$quantity Passes'),
          _detail('Amount Paid', _paymentAmount(payment)),
          _detail('Payment method', paymentMethod),
          _detail('Payment ID', paymentId),
          _detail('Status', status),
        ])),
        const SizedBox(height: 14),
        OutlinedButton(onPressed: () => launchUrl(Uri(scheme: 'mailto', path: 'support@spoda.ai')), style: OutlinedButton.styleFrom(foregroundColor: AppColors.acid, side: const BorderSide(color: AppColors.acid), shape: const RoundedRectangleBorder()), child: const Text('Need Help?')),
      ]),
    );
  }
}

class SavedBlogsPage extends StatefulWidget {
  const SavedBlogsPage({super.key, required this.postsLoader});
  final Future<List<BlogPost>> Function(Set<int>) postsLoader;
  @override State<SavedBlogsPage> createState() => _SavedBlogsPageState();
}

class _SavedBlogsPageState extends State<SavedBlogsPage> {
  late Future<List<BlogPost>> _posts = widget.postsLoader(Set<int>.from(_savedPostIds));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Saved Blogs'), backgroundColor: AppColors.surface),
    body: FutureBuilder<List<BlogPost>>(future: _posts, builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: AppColors.acid));
      if (snapshot.hasError) return Center(child: TextButton(onPressed: () => setState(() => _posts = widget.postsLoader(Set<int>.from(_savedPostIds))), child: const Text('Could not load saved blogs. Tap to retry.')));
      final posts = snapshot.data ?? const <BlogPost>[];
      if (posts.isEmpty) return const Center(child: Text('No saved blogs yet.', style: TextStyle(color: AppColors.muted)));
      return ListView.separated(padding: const EdgeInsets.all(14), itemCount: posts.length, separatorBuilder: (_, _) => const SizedBox(height: 8), itemBuilder: (context, index) {
        final post = posts[index];
        return Container(color: AppColors.surface, child: ListTile(
          leading: post.image.isEmpty ? const Icon(Icons.menu_book_outlined, color: AppColors.acid) : Image.network(post.image, width: 54, height: 64, fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.menu_book_outlined, color: AppColors.acid)),
          title: Text(post.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          subtitle: Text(post.excerpt, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
          trailing: IconButton(icon: const Icon(Icons.bookmark, color: AppColors.acid), onPressed: () => setState(() { _savedPostIds.remove(post.id); _posts = widget.postsLoader(Set<int>.from(_savedPostIds)); })),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BlogArticlePage(post: post))),
        ));
      });
    }),
  );
}

class BlogArticlePage extends StatelessWidget {
  const BlogArticlePage({super.key, required this.post});
  final BlogPost post;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Blogs'), backgroundColor: AppColors.surface),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      if (post.image.isNotEmpty) Image.network(post.image, height: 210, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
      const SizedBox(height: 14),
      Text(post.title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
      const SizedBox(height: 14),
      Text(post.content, style: const TextStyle(height: 1.55, color: AppColors.muted)),
    ]),
  );
}

class AccountSecurityPage extends StatefulWidget {
  const AccountSecurityPage({super.key, required this.email});
  final String email;
  @override State<AccountSecurityPage> createState() => _AccountSecurityPageState();
}

class _AccountSecurityPageState extends State<AccountSecurityPage> {
  bool _sending = false;
  Future<void> _sendReset() async {
    if (widget.email.isEmpty) return;
    setState(() => _sending = true);
    try {
      await AuthService.instance.requestPasswordReset(widget.email);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password reset link sent to your email.')));
    } on AuthException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally { if (mounted) setState(() => _sending = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Account & Security'), backgroundColor: AppColors.surface),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('ACCOUNT', style: TextStyle(color: AppColors.muted, fontSize: 10)),
      ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.email_outlined), title: const Text('Email'), subtitle: Text(widget.email.isEmpty ? 'No email on this account' : widget.email, style: const TextStyle(color: AppColors.muted))),
      const Divider(color: AppColors.border),
      const ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.lock_outline), title: Text('Password'), subtitle: Text('Send a password reset link to your email.', style: TextStyle(color: AppColors.muted, fontSize: 12))),
      const SizedBox(height: 8),
      OutlinedButton(onPressed: widget.email.isEmpty || _sending ? null : _sendReset, child: Text(_sending ? 'Sending…' : 'Reset password')),
    ]),
  );
}

class SettingsPage extends StatefulWidget { const SettingsPage({super.key}); @override State<SettingsPage> createState() => _SettingsPageState(); }
class _SettingsPageState extends State<SettingsPage> {
  final Map<String, bool> _values = {'Match Reminders': true, 'Live Match Updates': true, 'Prediction Updates': true, 'AI Insights': true, 'News': true, 'Blogs': false, 'Offers & Promotions': true};
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Notification Settings'), backgroundColor: AppColors.surface), body: ListView(children: [_section('MATCHES', ['Match Reminders', 'Live Match Updates']), _section('AI & PREDICTIONS', ['Prediction Updates', 'AI Insights']), _section('NEWS & MEDIA', ['News', 'Blogs']), _section('OFFERS', ['Offers & Promotions'])]));
  Widget _section(String title, List<String> names) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Padding(padding: const EdgeInsets.fromLTRB(16, 18, 16, 5), child: Text(title, style: const TextStyle(color: AppColors.muted, fontSize: 10))), ...names.map((name) => SwitchListTile(title: Text(name, style: const TextStyle(fontSize: 14)), subtitle: Text(_caption(name), style: const TextStyle(color: AppColors.muted, fontSize: 10)), value: _values[name]!, onChanged: (v) => setState(() => _values[name] = v))), const Divider(color: AppColors.border, height: 1)]);
  String _caption(String name) => switch (name) {'Match Reminders' => 'Get reminded before matches start', 'Live Match Updates' => 'Score, wickets, and key moments', 'Prediction Updates' => 'Get notified when new predictions are available', 'AI Insights' => 'Get notified about important AI match insights', 'News' => 'Breaking news and updates', 'Blogs' => 'New blog posts and articles', _ => 'Discounts, bonus passes, and more'};
}

class LegalDocumentPage extends StatelessWidget {
  const LegalDocumentPage({super.key, required this.title, required this.assetPath});
  final String title;
  final String assetPath;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title), backgroundColor: AppColors.surface),
        body: FutureBuilder<String>(
          future: rootBundle.loadString(assetPath),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: AppColors.acid));
            }
            if (snapshot.hasError) {
              return const Center(child: Text('Could not load this document.', style: TextStyle(color: AppColors.muted)));
            }
            final paragraphs = snapshot.data!.split(RegExp(r'\r?\n')).where((line) => line.trim().isNotEmpty);
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              children: paragraphs.map((paragraph) {
                final isHeading = RegExp(r'^(\d+(\.\d+)*\.?\s+|Effective Date:|Privacy Policy for Spoda$|Terms of Use$)').hasMatch(paragraph);
                return Padding(
                  padding: EdgeInsets.only(bottom: isHeading ? 10 : 14, top: isHeading ? 8 : 0),
                  child: Text(paragraph, style: TextStyle(
                    color: isHeading ? Colors.white : AppColors.muted,
                    fontSize: isHeading ? 15 : 13,
                    fontWeight: isHeading ? FontWeight.w700 : FontWeight.normal,
                    height: 1.55,
                  )),
                );
              }).toList(),
            );
          },
        ),
      );
}

class HelpSupportPage extends StatefulWidget {
  const HelpSupportPage({super.key});

  @override
  State<HelpSupportPage> createState() => _HelpSupportPageState();
}

class _HelpSupportPageState extends State<HelpSupportPage> {
  final _searchController = TextEditingController();
  final Set<int> _expanded = {0};

  static const _faqs = <(String, String)>[
    ('Is it 100% accurate?', 'No, since it is an AI, it can’t be 100% accurate, but historically SpodaAI has over 80% accuracy in match predictions.'),
    ('What types of predictions does Spoda AI do?', 'SpodaAI offers match winner prediction, batters, bowlers, innings score and wicket prediction.'),
    ('What tournaments does Spoda AI cover?', 'SpodaAI covers all bilateral series, ICC events, and all major leagues of UK, Australia, UAE, India, Nepal, US and SA.'),
    ('Can AI predict who will win today’s cricket match?', 'Yes, SpodaAI predicts who will win today’s match query with over 80% accuracy.'),
    ('How does Spoda AI make predictions?', 'SpodaAI uses past data and then uses advanced machine learning technology to make predictions, that’s how it outperforms peers.'),
    ('Which countries is Spoda AI available in?', 'SpodaAI is available in the UK, US, EU, Nepal, India, Australia, UAE, South Africa, Sri Lanka, New Zealand and Bangladesh.'),
    ('What is the value of paying for Spoda?', 'Purchasing the \$12 pack grants unlimited questions, match predictions, and fantasy team suggestions across 20 games.'),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final matches = _faqs.indexed.where((entry) => query.isEmpty ||
        entry.$2.$1.toLowerCase().contains(query) || entry.$2.$2.toLowerCase().contains(query));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Help & Support'),
        backgroundColor: AppColors.surface,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 24, 18, 32),
        children: [
          const Text('How Can we help?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 22),
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 14),
            decoration: const InputDecoration(
              hintText: 'Search for help....',
              hintStyle: TextStyle(color: AppColors.muted, fontSize: 13),
              prefixIcon: Icon(Icons.search, color: AppColors.muted),
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: EdgeInsets.symmetric(vertical: 12),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.border), borderRadius: BorderRadius.zero),
              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.acid), borderRadius: BorderRadius.zero),
            ),
          ),
          const SizedBox(height: 12),
          for (final entry in matches) _faqTile(entry.$1, entry.$2.$1, entry.$2.$2),
          const SizedBox(height: 28),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 24, 18, 26),
            color: AppColors.surface,
            child: Column(
              children: [
                Image.asset('assets/group.png', height: 62, fit: BoxFit.contain),
                const SizedBox(height: 18),
                const Text('Still have questions?', textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const Text('Can’t find the answer you’re looking for?\nPlease email the team at',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted, fontSize: 14, height: 1.6)),
                TextButton(
                  onPressed: () => launchUrl(Uri(scheme: 'mailto', path: 'support@spoda.ai')),
                  child: const Text('support@spoda.ai', style: TextStyle(color: AppColors.acid)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _faqTile(int index, String question, String answer) {
    final expanded = _expanded.contains(index);
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => expanded ? _expanded.remove(index) : _expanded.add(index)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 15),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(question, style: const TextStyle(fontSize: 13, height: 1.45))),
                const SizedBox(width: 12),
                Icon(expanded ? Icons.remove_circle_outline : Icons.add_circle_outline,
                    size: 17, color: AppColors.muted),
              ],
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(bottom: 15),
            child: Align(alignment: Alignment.centerLeft,
                child: Text(answer, style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.5))),
          ),
        const Divider(color: AppColors.border, height: 1),
      ],
    );
  }
}

class AboutSpodaPage extends StatelessWidget {
  const AboutSpodaPage({super.key});

  static const _team = <(String, String, String?)>[
    ('Vibhu Pillai', 'Founder & CEO', 'assets/vibhu.jpg'),
    ('Vivek AV', 'Co-Founder & Chief Data Scientist', 'assets/vivek.png'),
    ('Debsourabh Ghosh', 'Co-Founder & Head of Design', 'assets/debsourabh.png'),
    ('Adnan Mohammed', 'Marketing Content & Sports Analyst', null),
    ('Skanda Narasimha', 'Marketing Content & Sports Analyst', null),
    ('Ashutosh Warikoo', 'Infrastructure and Security', null),
    ('Mukesh Mahadev', 'Back-end Developer', null),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('About Spoda'), backgroundColor: AppColors.surface),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
          children: [
            const Center(
              child: Column(children: [
                Text('About us', style: TextStyle(color: AppColors.acid, fontSize: 12)),
                SizedBox(height: 14),
                Text('Our mission is to\nmake sports data\nsimple and accessible',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, height: 1.45, fontWeight: FontWeight.w500)),
              ]),
            ),
            const SizedBox(height: 52),
            const Text('Our team', style: TextStyle(color: AppColors.acid, fontSize: 12)),
            const SizedBox(height: 8),
            const Text('Team', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w500)),
            const SizedBox(height: 10),
            const Text('Meet Team Spoda: a cross-disciplinary team dedicated to creating exceptional customer products.',
                style: TextStyle(color: AppColors.muted, fontSize: 15, height: 1.55)),
            const SizedBox(height: 22),
            ..._team.map(_member),
          ],
        ),
      );

  Widget _member((String, String, String?) person) {
    final (name, role, image) = person;
    final initials = name.split(' ').where((part) => part.isNotEmpty).take(2).map((part) => part[0]).join();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(children: [
        CircleAvatar(
          radius: 35,
          backgroundColor: AppColors.surface,
          foregroundImage: image == null ? null : AssetImage(image),
          child: image == null ? Text(initials, style: const TextStyle(color: AppColors.acid, fontWeight: FontWeight.w700)) : null,
        ),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: const TextStyle(fontSize: 15)),
          const SizedBox(height: 4),
          Text(role, style: const TextStyle(color: AppColors.acid, fontSize: 13, height: 1.35)),
        ])),
      ]),
    );
  }
}

class SimplePage extends StatelessWidget { const SimplePage({super.key, required this.title}); final String title; @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(title), backgroundColor: AppColors.surface), body: const SizedBox.expand()); }
