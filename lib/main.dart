import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
          fontFamily: 'Arial',
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
    try {
      await AuthService.instance.storeProviderTokens(uri);
      final profile = await AuthService.instance.restoreProfile();
      if (!mounted) return;
      if (profile == null) throw const AuthException('Sign-in completed, but the profile could not be loaded.');
      setState(() => _session = Future.value(profile));
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
              const Spacer(),
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
  const _LoginPanel();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Lets get started', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
          const Text('with Spoda AI', style: TextStyle(fontSize: 25, color: AppColors.acid, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          const Text('Create your account and unlock a smarter cricket experience.', style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 26),
          _SocialLoginButton(label: 'Continue with Google', asset: 'assets/google.png', onPressed: () => _startSocialLogin(context, 'google')),
          const SizedBox(height: 9),
          _SocialLoginButton(label: 'Continue with Facebook', asset: 'assets/facebook.png', onPressed: () => _startSocialLogin(context, 'facebook')),
          const SizedBox(height: 9),
          _SocialLoginButton(label: 'Continue with email', asset: 'assets/email.png', onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EmailLoginPage()))),
          const SizedBox(height: 14),
          const Center(child: Text('By continuing, you agree to the Terms of Service\nand acknowledge our Privacy Policy.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 10))),
          const Spacer(),
          Center(child: RichText(text: TextSpan(style: const TextStyle(color: AppColors.muted, fontSize: 12), children: [
            const TextSpan(text: 'Already a member?  '),
            WidgetSpan(child: GestureDetector(onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EmailLoginPage())), child: const Text('Log in', style: TextStyle(color: AppColors.acid, fontWeight: FontWeight.w600)))),
          ]))),
          const SizedBox(height: 8),
          Center(child: RichText(text: TextSpan(style: const TextStyle(color: AppColors.muted, fontSize: 12), children: [
            const TextSpan(text: 'New to Spoda?  '),
            WidgetSpan(child: GestureDetector(onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CreateAccountPage())), child: const Text('Create an account', style: TextStyle(color: AppColors.acid, fontWeight: FontWeight.w600)))),
          ]))),
          const SizedBox(height: 12),
        ]),
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
  const EmailLoginPage({super.key});
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
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const HomePage()), (_) => false);
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
  bool _verified = false;
  String? _error;
  @override
  void initState() { super.initState(); _verifyToken(); }
  @override
  void dispose() { _password.dispose(); super.dispose(); }

  Future<void> _verifyToken() async {
    try { await AuthService.instance.verifyResetToken(widget.token); if (mounted) setState(() => _verified = true); }
    on AuthException catch (error) { if (mounted) setState(() => _error = error.message); }
  }

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
    if (scorecardTeam?['name'] != null) return scorecardTeam!['name'].toString();
    final value = raw['team$suffix'];
    if (value is Map) return (value['shortName'] ?? value['short_name'] ?? value['name'] ?? 'Team $suffix').toString();
    return (raw['teamName$suffix'] ?? raw['team$suffix Name'] ?? 'Team $suffix').toString();
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
    appBar: AppBar(backgroundColor: AppColors.background, title: const Text('SPODA', style: TextStyle(color: AppColors.acid, fontWeight: FontWeight.w900, letterSpacing: 2)), centerTitle: true, leading: IconButton(onPressed: _openMenu, icon: const Icon(Icons.menu, color: AppColors.acid))),
    body: _tab == 0 ? _homeDashboard() : _tab == 1 ? _matchPage() : _tab == 2 ? BlogListPage(preloaded: _posts) : const Center(child: Text('Profile')),
    bottomNavigationBar: NavigationBar(backgroundColor: AppColors.surface, indicatorColor: Colors.transparent, selectedIndex: _tab, onDestinationSelected: (i) => setState(() => _tab = i), destinations: const [NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'), NavigationDestination(icon: Icon(Icons.emoji_events_outlined), selectedIcon: Icon(Icons.emoji_events), label: 'Matches'), NavigationDestination(icon: Icon(Icons.newspaper_outlined), selectedIcon: Icon(Icons.newspaper), label: 'Blogs & News'), NavigationDestination(icon: Icon(Icons.account_circle_outlined), selectedIcon: Icon(Icons.account_circle), label: 'Profile')]),
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
          else ..._ordered((matchSnapshot.data ?? []).where((m) => m.group == 'tomorrow' && !_isDone(m)).toList()).take(3).map(_upcomingCard),
          const SizedBox(height: 16), _sectionHeader('News and Blogs', () => setState(() => _tab = 2)),
          if (postSnapshot.connectionState == ConnectionState.waiting) const SizedBox(height: 120, child: Center(child: CircularProgressIndicator(color: AppColors.acid)))
          else if (postSnapshot.hasError) TextButton(onPressed: () => setState(() => _posts = _loadPosts(4, 1)), child: const Text('Could not load posts. Tap to retry.'))
          else ..._blogPreviews(postSnapshot.data ?? []),
        ]),
      ),
    ),
  );
  Widget _sectionHeader(String title, VoidCallback action) => Padding(padding: const EdgeInsets.only(top: 18, bottom: 14), child: Row(children: [Expanded(child: Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800))), InkWell(onTap: action, child: const Row(children: [Text('View All', style: TextStyle(fontSize: 12, color: AppColors.muted)), SizedBox(width: 4), Icon(Icons.chevron_right, size: 20)]))]));
  Widget _liveSlider(List<MatchData> matches) {
    if (matches.isEmpty) return const SizedBox.shrink();
    return FutureBuilder<List<Map<String, dynamic>?>>(
      future: Future.wait(matches.map(_loadScorecard)),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const SizedBox.shrink();
        final cards = <(MatchData, Map<String, dynamic>?)>[];
        for (var i = 0; i < matches.length; i++) {
          final scorecard = snapshot.data != null && i < snapshot.data!.length ? snapshot.data![i] : null;
          if (scorecard == null ? _isLive(matches[i]) : _containsLiveStatus(scorecard)) cards.add((matches[i], scorecard));
        }
        if (cards.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sectionHeader('Live Matches', () => setState(() { _tab = 1; _matchStatus = 0; })),
          SizedBox(height: 295, child: PageView.builder(itemCount: cards.length, controller: PageController(viewportFraction: .96), itemBuilder: (context, i) => _LiveMatchCard(match: cards[i].$1, live: true, scorecard: cards[i].$2))),
          const SizedBox(height: 8),
        ]);
      },
    );
  }
  Widget _upcomingCard(MatchData match) => FutureBuilder<Map<String, dynamic>?>(future: _loadScorecard(match), builder: (context, snapshot) => _upcomingCardContent(match, snapshot.data));
  void _openMatchDetails(MatchData match, [Map<String, dynamic>? scorecard]) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MatchDetailPage(match: match, scorecard: scorecard)));
  Widget _upcomingCardContent(MatchData match, Map<String, dynamic>? scorecard) => Container(margin: const EdgeInsets.only(bottom: 10), decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border)), child: Column(children: [Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(match.tournament.toUpperCase(), style: const TextStyle(color: AppColors.acid, fontSize: 11, fontWeight: FontWeight.bold)), const SizedBox(height: 12), Row(children: [Expanded(child: Row(children: [_teamBadge(match, 'A', scorecard), const SizedBox(width: 8), Flexible(child: Text(match.teamName('A', scorecard: scorecard), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))), const Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('vs', style: TextStyle(color: AppColors.muted))), _teamBadge(match, 'B', scorecard), const SizedBox(width: 8), Flexible(child: Text(match.teamName('B', scorecard: scorecard), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)))])), Container(width: 1, height: 38, color: AppColors.border), const SizedBox(width: 12), Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text(_timeFor(match), style: const TextStyle(color: AppColors.muted, fontSize: 12)), const Text('Tomorrow', style: TextStyle(color: AppColors.muted, fontSize: 11))])])])), Container(color: const Color(0xFF111111), padding: const EdgeInsets.all(12), child: Row(children: [const Expanded(child: Text('•  Match prediction and insights available', style: TextStyle(fontSize: 12, color: Colors.white70))), TextButton(onPressed: () => _openMatchDetails(match, scorecard), style: TextButton.styleFrom(backgroundColor: AppColors.acid, foregroundColor: Colors.black, shape: const RoundedRectangleBorder()), child: const Text('Prediction  ›', style: TextStyle(fontWeight: FontWeight.bold)))]) )]));
  List<Widget> _blogPreviews(List<BlogPost> posts) { if (posts.isEmpty) return [const Text('No posts found.', style: TextStyle(color: AppColors.muted))]; return [if (posts.isNotEmpty) _featuredPost(posts.first), ...posts.skip(1).map((post) => _postTile(post))]; }
  Widget _featuredPost(BlogPost post) => InkWell(onTap: () => _showPost(post), child: Container(height: 220, margin: const EdgeInsets.only(bottom: 10), decoration: BoxDecoration(border: Border.all(color: AppColors.border), image: post.image.isEmpty ? null : DecorationImage(image: NetworkImage(post.image), fit: BoxFit.cover, onError: (_, _) {})), child: Container(padding: const EdgeInsets.all(16), decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black12, Colors.black87], stops: [.12, 1])), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [const Text('▣ Blogs', style: TextStyle(color: Colors.greenAccent)), const SizedBox(height: 8), Text(post.title, maxLines: 2, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), const SizedBox(height: 6), Text(post.excerpt, maxLines: 2, style: const TextStyle(fontSize: 12, color: Colors.white70)), const SizedBox(height: 8), const Text('◷  8 min read  ·  Latest', style: TextStyle(color: AppColors.muted, fontSize: 11))]))));
  Widget _postTile(BlogPost post) => InkWell(onTap: () => _showPost(post), child: Container(height: 154, margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(11), decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border)), child: Row(children: [if (post.image.isNotEmpty) ClipRRect(child: Image.network(post.image, width: 96, height: 130, fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(width: 96, height: 130, color: AppColors.border, child: const Icon(Icons.image)))), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [const Text('▣ Blogs', style: TextStyle(color: Colors.greenAccent, fontSize: 12)), const SizedBox(height: 7), Text(post.title, maxLines: 2, style: const TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 6), Text(post.excerpt, maxLines: 2, style: const TextStyle(color: AppColors.muted, fontSize: 12))]))])));
  void _showPost(BlogPost post) => showDialog<void>(context: context, builder: (context) => Dialog(backgroundColor: AppColors.surface, child: SizedBox(height: MediaQuery.sizeOf(context).height * .8, child: Column(children: [if (post.image.isNotEmpty) Image.network(post.image, height: 200, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()), Padding(padding: const EdgeInsets.all(16), child: Text(post.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20))), Expanded(child: SingleChildScrollView(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(post.content))), TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))]))));
  String _timeFor(MatchData m) { final d = m.startDate?.toLocal(); if (d == null) return '04:00 PM'; final hour = d.hour % 12 == 0 ? 12 : d.hour % 12; return '${hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}'; }
  Widget _teamBadge(MatchData match, String suffix, [Map<String, dynamic>? scorecard]) { final url = match.teamFlag(suffix, scorecard: scorecard); return url == null || url.isEmpty ? const SizedBox.shrink() : ClipOval(child: Image.network(url, width: 22, height: 22, fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.flag, size: 18, color: AppColors.muted))); }
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
                final matches = _filtered(snapshot.data ?? []);
                if (matches.isEmpty) {
                  final noMatchesAtAll = snapshot.data?.isEmpty ?? true;
                  return _empty(noMatchesAtAll ? 'No matches are available right now.' : 'No matches in this category.');
                }
                return RefreshIndicator(
                  color: AppColors.acid,
                  onRefresh: () async {
                    final future = _loadMatches();
                    setState(() => _matches = future);
                    await future;
                  },
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                    children: [
                      ...matches.map((m) => FutureBuilder<Map<String, dynamic>?>(future: _loadScorecard(m), builder: (context, scorecard) => _MatchCard(match: m, live: _isLive(m), showPrediction: !_isDone(m), scorecard: scorecard.data, onTap: () => _openMatchDetails(m, scorecard.data)))),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      );
  Widget _empty(String text, {bool retry = false}) => Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)), if (retry) TextButton(onPressed: () => setState(() => _matches = _loadMatches()), child: const Text('Try again'))])));
  void _openMenu() => showGeneralDialog<void>(context: context, barrierDismissible: true, barrierLabel: 'Close menu', barrierColor: Colors.black54, transitionDuration: const Duration(milliseconds: 200), pageBuilder: (_, _, _) => Align(alignment: Alignment.centerRight, child: SizedBox(width: MediaQuery.sizeOf(context).width * .84, height: double.infinity, child: _SideMenu(onMatches: () { Navigator.of(context).pop(); setState(() => _tab = 1); }))), transitionBuilder: (_, animation, _, child) => SlideTransition(position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(animation), child: child));
}

class BlogPost {
  const BlogPost({required this.title, required this.excerpt, required this.content, required this.image});
  final String title, excerpt, content, image;

  factory BlogPost.fromJson(Map<String, dynamic> json) {
    String clean(Object? value) => value is Map
        ? (value['rendered'] ?? '').toString().replaceAll(RegExp('<[^>]*>'), '').replaceAll('&amp;', '&').replaceAll('&#8217;', '’').trim()
        : (value ?? '').toString();
    final embedded = json['_embedded'];
    final media = embedded is Map && embedded['wp:featuredmedia'] is List && (embedded['wp:featuredmedia'] as List).isNotEmpty
        ? (embedded['wp:featuredmedia'] as List).first
        : null;
    return BlogPost(
      title: clean(json['title']),
      excerpt: clean(json['excerpt']),
      content: clean(json['content']),
      image: (json['thumbnailUrl'] ?? (media is Map ? media['source_url'] : null) ?? '').toString(),
    );
  }
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
        child: Container(height: 160, margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border)), child: Row(children: [if (post.image.isNotEmpty) Image.network(post.image, width: 110, height: 135, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox(width: 110, child: Icon(Icons.image))), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [const Text('▣ Blogs', style: TextStyle(color: Colors.greenAccent)), const SizedBox(height: 8), Text(post.title, maxLines: 2, style: const TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 6), Text(post.excerpt, maxLines: 3, style: const TextStyle(color: AppColors.muted, fontSize: 12))]))])),
      );
    },
  );
}

class _LiveMatchCard extends StatelessWidget {
  const _LiveMatchCard({required this.match, required this.live, this.scorecard});
  final MatchData match;
  final bool live;
  final Map<String, dynamic>? scorecard;
  @override Widget build(BuildContext context) => Container(margin: const EdgeInsets.only(right: 10, bottom: 4), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF090909), border: Border.all(color: AppColors.acid)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Icon(Icons.circle, size: 8, color: live ? AppColors.red : AppColors.muted), const SizedBox(width: 6), Text(live ? 'LIVE' : match.status.toUpperCase(), style: const TextStyle(color: AppColors.red, fontSize: 11, fontWeight: FontWeight.bold)), const SizedBox(width: 12), Expanded(child: Text('[${match.tournament.toUpperCase()}]', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.acid, fontSize: 11, fontWeight: FontWeight.bold)))]), const Divider(color: AppColors.border), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_team(match, 'A'), const Text('VS', style: TextStyle(color: AppColors.muted)), _team(match, 'B')]), const Spacer(), Container(width: double.infinity, padding: const EdgeInsets.all(10), color: AppColors.surface, child: Text(match.score.isEmpty ? 'Live match updates and insights' : match.score, style: const TextStyle(color: AppColors.acid, fontSize: 13))), const SizedBox(height: 10), const Center(child: Text('View Full Prediction →', style: TextStyle(fontWeight: FontWeight.bold)))]));
  Widget _team(MatchData match, String side) => Row(mainAxisSize: MainAxisSize.min, children: [if (match.teamFlag(side, scorecard: scorecard) != null && match.teamFlag(side, scorecard: scorecard)!.isNotEmpty) ClipOval(child: Image.network(match.teamFlag(side, scorecard: scorecard)!, width: 22, height: 22, errorBuilder: (_, _, _) => const SizedBox.shrink())), const SizedBox(width: 5), Text(match.teamName(side, scorecard: scorecard), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold))]);
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({required this.match, required this.live, required this.showPrediction, required this.onTap, this.scorecard});
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
            Text(match.tournament.toUpperCase(), style: const TextStyle(color: AppColors.muted, fontSize: 10, fontWeight: FontWeight.w700)),
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
                  child: const Text('Prediction  ›', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
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
    return Row(children: [
      if (logo != null && logo.isNotEmpty)
        ClipOval(child: Image.network(logo, width: 30, height: 30, fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.shield, size: 25, color: AppColors.muted)))
      else
        const Icon(Icons.shield, size: 25, color: AppColors.muted),
      const SizedBox(width: 8),
      Expanded(child: Text(match.teamName(side, scorecard: scorecard), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
    ]);
  }
}

class MatchDetailPage extends StatefulWidget {
  const MatchDetailPage({super.key, required this.match, this.scorecard});
  final MatchData match;
  final Map<String, dynamic>? scorecard;

  @override
  State<MatchDetailPage> createState() => _MatchDetailPageState();
}

class _MatchDetailPageState extends State<MatchDetailPage> {
  static const _tabs = ['Pre-match', 'Ai Signal', 'Squads', 'Stats'];
  static const _prompts = ['Top Runs?', 'Top Performer?', 'Match Winner?'];
  final _question = TextEditingController();
  int _selectedTab = 0;
  int _squadFilter = 0;
  int _batterSubtab = 0;
  int _batterMetric = 0;
  int _batterThreshold = 0;
  int _comparisonMetric = 0;
  String? _selectedBatsmanId;
  Future<List<Map<String, dynamic>>> _topBatters = Future.value(const []);
  Future<Object?> _batterComparison = Future.value(null);
  late final Future<List<Map<String, dynamic>>> _players = _loadPlayers();

  static const _batterMetrics = ['Run Scored', 'Strike Rate', 'Balls Faced'];
  static const _comparisonMetrics = ['Dismissal', 'Strike rate'];
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
      return _decodePlayers(jsonDecode(body));
    } finally { client.close(force: true); }
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

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.background,
          titleSpacing: 0,
          title: Text(widget.match.tournament, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
        ),
        body: SafeArea(child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 12), child: Row(children: [
            Expanded(child: _detailTeam(widget.match, 'A')),
            Column(children: [Text(widget.match.status, style: const TextStyle(color: AppColors.acid, fontSize: 11)), const SizedBox(height: 3), Text(widget.match.startDate == null ? 'Match details' : _detailTime(widget.match.startDate!), style: const TextStyle(color: AppColors.muted, fontSize: 11))]),
            Expanded(child: _detailTeam(widget.match, 'B', rightAlign: true)),
          ])),
          SizedBox(height: 44, child: Row(children: List.generate(_tabs.length, (i) => Expanded(child: InkWell(
            onTap: () => setState(() => _selectedTab = i),
            child: Column(children: [Expanded(child: Center(child: Text(_tabs[i], maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: _selectedTab == i ? Colors.white : AppColors.muted, fontWeight: _selectedTab == i ? FontWeight.w700 : FontWeight.w400)))), Container(height: 2, color: _selectedTab == i ? AppColors.acid : Colors.transparent)]),
          ))))),
          Expanded(child: _selectedTab == 2 ? _squadsContent() : const SizedBox.expand()),
          _askAiSection(),
        ])),
      );

  Widget _squadsContent() => Column(children: [
    const SizedBox(height: 12),
    SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
      _squadChip('Whole Squad', 0), const SizedBox(width: 8), _squadChip('Top Batter', 1), const SizedBox(width: 8), _squadChip('Top Bowler', 2),
    ])),
    const SizedBox(height: 12),
    if (_squadFilter == 1) ...[
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Row(children: [
        Expanded(child: _batterModeChip('Top Batter', 0)),
        const SizedBox(width: 8),
        Expanded(child: _batterModeChip('Batter Vs Bowler', 1)),
      ])),
      const SizedBox(height: 10),
      if (_batterSubtab == 0) ...[
        const Padding(padding: EdgeInsets.fromLTRB(12, 4, 12, 10), child: Align(alignment: Alignment.centerLeft, child: Text('Top Batsman Probabilities', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Row(children: [
          Expanded(child: _batterDropdown<int>(value: _batterMetric, items: List.generate(_batterMetrics.length, (i) => DropdownMenuItem(value: i, child: Text(_batterMetrics[i]))), onChanged: _selectBatterMetric)),
          const SizedBox(width: 8),
          Expanded(child: _batterDropdown<int>(value: _batterThreshold, items: List.generate(_batterThresholds.length, (i) => DropdownMenuItem(value: i, child: Text(_batterThresholds[i]))), onChanged: _selectBatterThreshold)),
        ])),
      ] else
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
        })),
    ],
    Expanded(child: _squadFilter == 1 && _batterSubtab == 1
      ? _comparisonResults()
      : FutureBuilder<List<Map<String, dynamic>>>(future: _squadFilter == 1 ? _topBatters : _players, builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: AppColors.acid));
      if (snapshot.hasError) return Center(child: Text(_squadFilter == 1 ? 'Could not load top batter data' : 'Could not load players', style: const TextStyle(color: AppColors.muted)));
      final players = snapshot.data ?? [];
      if (_squadFilter == 1) {
        if (players.isEmpty) return const Center(child: Text('No top batter data available', style: TextStyle(color: AppColors.muted)));
        return ListView.builder(itemCount: players.length, itemBuilder: (context, index) => _topBatterRow(players[index]));
      }
      final filtered = players.where((player) {
        final role = '${player['role'] ?? player['playingRole'] ?? player['playing_role'] ?? player['position'] ?? ''}'.toLowerCase();
        if (_squadFilter == 1) return role.contains('bat');
        if (_squadFilter == 2) return role.contains('bowl');
        return true;
      }).toList();
      if (filtered.isEmpty) return Center(child: Text(players.isEmpty ? 'No squad information available' : 'No players in this category', style: const TextStyle(color: AppColors.muted)));
      return ListView.builder(itemCount: filtered.length, itemBuilder: (context, index) {
        final player = filtered[index];
        final name = (player['playerName'] ?? player['player_name'] ?? player['fullName'] ?? player['name'] ?? 'Player').toString();
        final role = (player['role'] ?? player['playingRole'] ?? player['playing_role'] ?? player['position'] ?? '').toString();
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

  String? _batsmanId(Map<String, dynamic> player) => (player['playerId'] ?? player['player_id'] ?? player['batsmanId'] ?? player['batsman_id'] ?? player['id'])?.toString();
  String _playerName(Map<String, dynamic> player) => (player['playerName'] ?? player['player_name'] ?? player['fullName'] ?? player['name'] ?? 'Player').toString();

  Widget _batterModeChip(String label, int value) => InkWell(
    onTap: () => setState(() {
      _batterSubtab = value;
      if (value == 1) _loadBatterComparison();
    }),
    child: Container(height: 32, alignment: Alignment.center, decoration: BoxDecoration(color: _batterSubtab == value ? const Color(0xFF292929) : AppColors.surface, border: Border.all(color: _batterSubtab == value ? AppColors.border : AppColors.border)), child: Text(label, style: TextStyle(fontSize: 11, color: _batterSubtab == value ? Colors.white : AppColors.muted))),
  );

  Widget _comparisonResults() => FutureBuilder<Object?>(future: _batterComparison, builder: (context, snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: AppColors.acid));
    if (snapshot.hasError) return const Center(child: Text('Could not load batter comparison', style: TextStyle(color: AppColors.muted)));
    final rows = _comparisonRows(snapshot.data);
    if (_selectedBatsmanId == null) return const Center(child: Text('Select a batter to view comparison', style: TextStyle(color: AppColors.muted)));
    if (rows.isEmpty) return const Center(child: Text('No comparison data available', style: TextStyle(color: AppColors.muted)));
    return ListView(
      children: rows.map((row) => Container(
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
        child: ListTile(
          dense: true,
          title: Text(row.$1, style: const TextStyle(fontSize: 12)),
          subtitle: Text(_comparisonMetric == 0 ? 'Probable Dismissal Rate' : 'Probable Strike Rate', style: const TextStyle(fontSize: 10, color: AppColors.muted)),
          trailing: Text(row.$2, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.acid)),
        ),
      )).toList(),
    );
  });

  List<(String, String)> _comparisonRows(Object? data, [String? inheritedBowler]) {
    if (data is List) {
      return [for (final item in data) ..._comparisonRows(item, inheritedBowler)];
    }
    if (data is! Map) return [];
    final map = Map<String, dynamic>.from(data);
    final bowler = (map['playerName'] ?? map['player_name'] ?? map['bowlerName'] ?? map['bowler_name'] ?? map['bowler'] ?? map['fullName'] ?? map['name'] ?? inheritedBowler)?.toString();
    final metricProbability = _comparisonMetric == 0
        ? (map['probableDismissalRate'] ?? map['probable_dismissal_rate'])
        : (map['probableStrikeRate'] ?? map['probable_strike_rate']);
    final probability = metricProbability ?? map['probability'] ?? map['dismissalProbability'] ?? map['dismissal_probability'] ?? map['strikeRate'] ?? map['strike_rate'] ?? map['probabilityPercentage'] ?? map['percentage'] ?? map['value'];
    if (bowler != null && probability != null && probability is! Map && probability is! List) {
      final value = probability.toString();
      return [(bowler, value.contains('%') ? value : '$value%')];
    }
    final rows = <(String, String)>[];
    for (final key in ['data', 'results', 'bowlers', 'comparisons']) {
      if (map[key] != null) rows.addAll(_comparisonRows(map[key], inheritedBowler));
    }
    if (rows.isNotEmpty) return rows;
    for (final entry in map.entries) {
      if (const {'code', 'message', 'squadAnnounced', 'squad_announced'}.contains(entry.key)) continue;
      if (entry.value is Map || entry.value is List) {
        rows.addAll(_comparisonRows(entry.value, entry.key));
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
  }), child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(color: _squadFilter == index ? AppColors.acid : AppColors.surface, border: Border.all(color: _squadFilter == index ? AppColors.acid : AppColors.border)),
    child: Text(label, style: TextStyle(color: _squadFilter == index ? Colors.black : AppColors.muted, fontSize: 11, fontWeight: FontWeight.w600)),
  ));

  Widget _detailTeam(MatchData match, String side, {bool rightAlign = false}) {
    final name = match.teamName(side, scorecard: widget.scorecard);
    final logo = match.teamFlag(side, scorecard: widget.scorecard);
    final badge = logo == null || logo.isEmpty
        ? const Icon(Icons.shield, size: 25, color: AppColors.muted)
        : ClipOval(child: Image.network(logo, width: 25, height: 25, fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.shield, size: 25, color: AppColors.muted)));
    return Row(mainAxisAlignment: rightAlign ? MainAxisAlignment.end : MainAxisAlignment.start, children: [
      if (!rightAlign) ...[badge, const SizedBox(width: 7)],
      Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
      if (rightAlign) ...[const SizedBox(width: 7), badge],
    ]);
  }

  String _detailTime(DateTime date) {
    final local = date.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    return '${hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')} ${local.hour >= 12 ? 'PM' : 'AM'}';
  }

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
            Expanded(child: TextField(controller: _question, style: const TextStyle(fontSize: 12), decoration: const InputDecoration(hintText: 'Ask anything about this match...', hintStyle: TextStyle(color: AppColors.muted, fontSize: 11), filled: true, fillColor: AppColors.surface, contentPadding: EdgeInsets.symmetric(horizontal: 9, vertical: 10), enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.border), borderRadius: BorderRadius.zero), focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.acid), borderRadius: BorderRadius.zero)))),
            const SizedBox(width: 6),
            SizedBox(height: 38, width: 38, child: IconButton.filled(onPressed: () {}, style: IconButton.styleFrom(backgroundColor: AppColors.acid, foregroundColor: AppColors.background, shape: const RoundedRectangleBorder(), padding: EdgeInsets.zero), icon: const Icon(Icons.send, size: 18))),
          ]),
        ]),
      );
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
      if (profile != null) ListTile(leading: const Icon(Icons.logout, color: AppColors.muted), title: const Text('Sign out'), onTap: () async { await AuthService.instance.logout(); if (context.mounted) Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LandingPage()), (_) => false); }),
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

class SettingsPage extends StatefulWidget { const SettingsPage({super.key}); @override State<SettingsPage> createState() => _SettingsPageState(); }
class _SettingsPageState extends State<SettingsPage> {
  final Map<String, bool> _values = {'Match Reminders': true, 'Live Match Updates': true, 'Prediction Updates': true, 'AI Insights': true, 'News': true, 'Blogs': false, 'Offers & Promotions': true};
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Settings'), backgroundColor: AppColors.surface), body: ListView(children: [_section('MATCHES', ['Match Reminders', 'Live Match Updates']), _section('AI & PREDICTIONS', ['Prediction Updates', 'AI Insights']), _section('NEWS & MEDIA', ['News', 'Blogs']), _section('OFFERS', ['Offers & Promotions'])]));
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
