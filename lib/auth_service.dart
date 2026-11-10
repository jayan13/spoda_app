import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AuthSession {
  const AuthSession({required this.accessToken, required this.refreshToken, required this.id, required this.fullName, required this.email});
  final String accessToken;
  final String refreshToken;
  final String id;
  final String fullName;
  final String email;

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        accessToken: json['access_token']?.toString() ?? '',
        refreshToken: json['refresh_token']?.toString() ?? '',
        id: json['id']?.toString() ?? '',
        fullName: json['fullName']?.toString() ?? '',
        email: json['email']?.toString() ?? '',
      );
}

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  static final Uri _base = Uri.parse('https://api.spoda.ai');
  static const String redirectUrl = 'spoda://auth/callback';
  static const String passwordResetRedirectUrl = 'spoda://auth/reset';
  static const _storage = FlutterSecureStorage();
  static const _accessKey = 'spoda_access_token';
  static const _refreshKey = 'spoda_refresh_token';
  final http.Client _client = http.Client();
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? get profile => _profile;

  Uri _uri(String path) => _base.resolve(path);

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    try {
      final response = await _client.post(_uri(path), headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'}, body: jsonEncode(body));
      final decoded = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);
      final data = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
      if (response.statusCode < 200 || response.statusCode >= 300) throw AuthException(_message(data, response.statusCode));
      return data;
    } on AuthException {
      rethrow;
    } on FormatException {
      throw const AuthException('The server returned an unexpected response.');
    } catch (_) {
      throw const AuthException('Could not reach Spoda. Check your connection and try again.');
    }
  }

  String _message(Map<String, dynamic> data, int status) {
    final message = data['message'];
    if (message is List) return message.join('\n');
    if (message is String && message.isNotEmpty) return message;
    return switch (status) { 401 => 'Email or password is incorrect.', 403 => 'Please verify your email before logging in.', 409 => 'An account with this email already exists.', _ => 'Request failed ($status). Please try again.' };
  }

  Future<void> register({required String fullName, required String email, required String password}) async {
    await _post('/auth/sign-up', {'fullName': fullName, 'email': email, 'password': password, 'redirectUrl': redirectUrl});
  }

  Future<AuthSession> login({required String email, required String password}) async {
    final session = AuthSession.fromJson(await _post('/auth/sign-in', {'email': email, 'password': password}));
    if (session.accessToken.isEmpty) throw const AuthException('Login succeeded without an access token.');
    await _store(session);
    return session;
  }

  Future<void> _store(AuthSession session) async {
    await _storage.write(key: _accessKey, value: session.accessToken);
    if (session.refreshToken.isNotEmpty) await _storage.write(key: _refreshKey, value: session.refreshToken);
  }

  Future<void> storeProviderTokens(Uri callback) async {
    final fragment = callback.fragment.isEmpty ? <String, String>{} : Uri.splitQueryString(callback.fragment);
    final access = callback.queryParameters['access_token'] ?? fragment['access_token'];
    final refresh = callback.queryParameters['refresh_token'] ?? fragment['refresh_token'] ?? '';
    if (access == null || access.isEmpty) throw const AuthException('The provider callback did not include an access token.');
    await _store(AuthSession(accessToken: access, refreshToken: refresh, id: '', fullName: '', email: ''));
  }

  Future<Map<String, dynamic>?> restoreProfile() async {
    final token = await _storage.read(key: _accessKey);
    if (token == null || token.isEmpty) return null;
    try {
      final response = await _client.get(_uri('/users/profile'), headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'});
      if (response.statusCode == 401 || response.statusCode == 403) { await logout(); return null; }
      if (response.statusCode < 200 || response.statusCode >= 300) throw AuthException(_message(_decodeMap(response.body), response.statusCode));
      _profile = _decodeMap(response.body);
      return _profile;
    } catch (_) {
      return null;
    }
  }

  Future<void> requestPasswordReset(String email) async {
    await _post('/auth/forgot-password', {'email': email, 'redirectUrl': passwordResetRedirectUrl});
  }

  Future<void> verifyEmail(String token) async {
    await _post('/auth/email/verify', {'token': token});
  }

  Future<void> changePassword({required String token, required String password}) async {
    await _post('/auth/change-password', {'token': token, 'newPassword': password});
  }

  Future<String?> accessToken() => _storage.read(key: _accessKey);

  Future<int> remainingPasses() async {
    final token = await accessToken();
    if (token == null || token.isEmpty) return 0;
    final uri = _base.replace(
      path: '/passes/remaining',
      queryParameters: {'_t': DateTime.now().millisecondsSinceEpoch.toString()},
    );
    try {
      final response = await _client.get(uri, headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      });
      if (response.statusCode == 401 || response.statusCode == 403) return 0;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AuthException(_message(_decodeMap(response.body), response.statusCode));
      }
      return _findPassCount(jsonDecode(response.body)) ?? 0;
    } on AuthException {
      rethrow;
    } catch (_) {
      throw const AuthException('Could not load the remaining pass count.');
    }
  }

  Future<List<String>> unlockedMatches() async {
    final token = await accessToken();
    if (token == null || token.isEmpty) return const [];
    final uri = _base.replace(path: '/passes/unlocked-matches', queryParameters: {'_t': DateTime.now().millisecondsSinceEpoch.toString()});
    try {
      final response = await _client.get(uri, headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'});
      if (response.statusCode < 200 || response.statusCode >= 300) throw AuthException(_message(_decodeMap(response.body), response.statusCode));
      final data = _decodeMap(response.body)['unlockedMatches'];
      return data is List ? data.map((value) => value.toString()).toList() : const [];
    } on AuthException { rethrow; } catch (_) { throw const AuthException('Could not check unlocked matches.'); }
  }

  Future<bool> freeTrialEligible() async {
    final token = await accessToken();
    if (token == null || token.isEmpty) return false;
    final uri = _base.replace(path: '/passes/free-trial-eligibility', queryParameters: {'_t': DateTime.now().millisecondsSinceEpoch.toString()});
    try {
      final response = await _client.get(uri, headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'});
      if (response.statusCode < 200 || response.statusCode >= 300) throw AuthException(_message(_decodeMap(response.body), response.statusCode));
      return _decodeMap(response.body)['trialEligibility'] == true;
    } on AuthException { rethrow; } catch (_) { throw const AuthException('Could not check free trial eligibility.'); }
  }

  Future<void> usePass(String matchId) async => _authorizedPost('/passes/use', {'matchId': matchId});

  Future<void> activateFreeTrial(String matchId) async => _authorizedPost('/passes/free-trial-activate', {'matchId': matchId});

  Future<Map<String, dynamic>> sendAgentMessage({required String collectionId, required String question, required String conversationId, required bool isLive}) =>
      _authorizedPost('/messages/agent', {'collectionId': collectionId, 'question': question, 'conversationId': conversationId, 'isLive': isLive});

  Future<Map<String, dynamic>> _authorizedPost(String path, Map<String, dynamic> body) async {
    final token = await accessToken();
    if (token == null || token.isEmpty) throw const AuthException('Please log in to continue.');
    try {
      final response = await _client.post(_uri(path), headers: {'Content-Type': 'application/json', 'Accept': 'application/json', 'Authorization': 'Bearer $token'}, body: jsonEncode(body));
      final data = response.body.isEmpty ? <String, dynamic>{} : _decodeMap(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) throw AuthException(_message(data, response.statusCode));
      return data;
    } on AuthException { rethrow; } catch (_) { throw const AuthException('Could not reach Spoda. Check your connection and try again.'); }
  }

  Future<List<Map<String, dynamic>>> passHistory({bool isUsed = true}) async {
    final token = await accessToken();
    if (token == null || token.isEmpty) return const [];
    final uri = _base.replace(
      path: '/passes/history',
      queryParameters: {'isUsed': isUsed.toString()},
    );
    try {
      final response = await _client.get(uri, headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      });
      if (response.statusCode == 401 || response.statusCode == 403) return const [];
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AuthException(_message(_decodeMap(response.body), response.statusCode));
      }
      final decoded = jsonDecode(response.body);
      final rows = decoded is Map ? decoded['passHistory'] : null;
      if (rows is! List) return const [];
      return rows.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList();
    } on AuthException {
      rethrow;
    } catch (_) {
      throw const AuthException('Could not load pass history. Check your connection and try again.');
    }
  }

  Future<List<Map<String, dynamic>>> paymentHistory() async {
    final token = await accessToken();
    if (token == null || token.isEmpty) return const [];
    try {
      final response = await _client.get(_uri('/payments/history'), headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      });
      if (response.statusCode == 401 || response.statusCode == 403) return const [];
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AuthException(_message(_decodeMap(response.body), response.statusCode));
      }
      Object? rows = jsonDecode(response.body);
      for (var depth = 0; depth < 5 && rows is Map; depth++) {
        Object? next;
        for (final key in ['paymentHistory', 'payments', 'history', 'items', 'data', 'value']) {
          if (rows.containsKey(key)) {
            next = rows[key];
            break;
          }
        }
        if (next == null) break;
        rows = next;
      }
      if (rows is! List) return const [];
      return rows.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList();
    } on AuthException {
      rethrow;
    } catch (_) {
      throw const AuthException('Could not load purchase history. Check your connection and try again.');
    }
  }

  Future<List<Map<String, dynamic>>> pricingPlans({required String country, String? state}) async {
    final query = <String, String>{'country': country};
    if (state != null && state.isNotEmpty) query['state'] = state;
    final uri = _base.replace(
      path: '/pricing/plans',
      queryParameters: query,
    );
    try {
      final response = await _client.get(uri, headers: const {'Accept': 'application/json'});
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AuthException(_message(_decodeMap(response.body), response.statusCode));
      }
      final decoded = jsonDecode(response.body);
      final rows = decoded is List ? decoded : decoded is Map ? (decoded['value'] ?? decoded['data'] ?? decoded['plans']) : null;
      if (rows is! List) return const [];
      return rows.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList();
    } on AuthException {
      rethrow;
    } catch (_) {
      throw const AuthException('Could not load pricing plans. Check your connection and try again.');
    }
  }

  Future<void> logout() async {
    _profile = null;
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }

  static Map<String, dynamic> _decodeMap(String body) {
    final value = jsonDecode(body);
    return value is Map<String, dynamic> ? value : <String, dynamic>{};
  }

  static int? _findPassCount(Object? value) {
    const countKeys = {
      'remaining', 'remainingpasses', 'passesremaining', 'passcount', 'remainingpasscount',
      'passremaining', 'availablepasses', 'remaining_passes', 'count',
    };
    if (value is num) return value.toInt();
    if (value is Map) {
      for (final entry in value.entries) {
        if (countKeys.contains(entry.key.toString().toLowerCase())) {
          if (entry.value is num) return (entry.value as num).toInt();
          final parsed = int.tryParse(entry.value?.toString() ?? '');
          if (parsed != null) return parsed;
        }
      }
      for (final nested in value.values) {
        final count = _findPassCount(nested);
        if (count != null) return count;
      }
    }
    if (value is List) {
      for (final nested in value) {
        final count = _findPassCount(nested);
        if (count != null) return count;
      }
    }
    return null;
  }
}
