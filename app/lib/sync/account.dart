import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../data/db.dart';
import '../data/keys.dart';

export '../data/keys.dart';

/// The hosted sync service. The sign-in screen can point at another one
/// (a local `go run ./cmd/opentodo-server` is http://127.0.0.1:8686).
const defaultServerUrl = 'https://todo.liaoxingyi.com';

class Account {
  const Account({
    required this.serverUrl,
    required this.token,
    required this.email,
    required this.userId,
  });

  final String serverUrl;
  final String token;
  final String email;
  final String userId;

  static Future<Account?> load(AppDatabase db) async {
    final token = await db.getValue(Keys.token);
    if (token == null) return null;
    return Account(
      serverUrl: await db.getValue(Keys.server) ?? defaultServerUrl,
      token: token,
      email: await db.getValue(Keys.email) ?? '',
      userId: await db.getValue(Keys.userId) ?? '',
    );
  }

  Future<void> save(AppDatabase db) => db.transaction(() async {
        await db.setValue(Keys.server, serverUrl);
        await db.setValue(Keys.token, token);
        await db.setValue(Keys.email, email);
        await db.setValue(Keys.userId, userId);
      });
}

/// An error the person can act on, already in their words.
class SyncException implements Exception {
  const SyncException(this.code, this.message);

  final String code;
  final String message;

  bool get isAuth => code == 'unauthorized';

  @override
  String toString() => message;
}

const _messages = {
  'invalid_email': '邮箱格式不对',
  'weak_password': '密码至少 8 位',
  'email_taken': '这个邮箱已经注册过，请直接登录',
  'invalid_credentials': '邮箱或密码不正确',
  'unauthorized': '登录已失效，请重新登录',
  'rate_limited': '尝试太频繁，请一分钟后再试',
};

SyncException errorFrom(http.Response r) {
  String code = 'http_${r.statusCode}';
  try {
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    code = (body['error'] as Map<String, dynamic>)['code'] as String;
  } catch (_) {}
  return SyncException(code, _messages[code] ?? '服务器出错（${r.statusCode}），请稍后再试');
}

SyncException networkError(Object e) =>
    SyncException('network', '连不上服务器，请检查网络或服务器地址（$e）');

String normalizeServerUrl(String url) {
  var u = url.trim();
  if (u.isEmpty) return defaultServerUrl;
  if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'https://$u';
  while (u.endsWith('/')) {
    u = u.substring(0, u.length - 1);
  }
  return u;
}

class AuthApi {
  AuthApi(this.client);
  final http.Client client;

  Future<Account> signIn({
    required String serverUrl,
    required String email,
    required String password,
    required bool register,
  }) async {
    final server = normalizeServerUrl(serverUrl);
    final http.Response r;
    try {
      r = await client
          .post(
            Uri.parse('$server/v1/auth/${register ? 'register' : 'login'}'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': email.trim(),
              'password': password,
              'device': Platform.operatingSystem,
            }),
          )
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      throw networkError(e);
    }
    if (r.statusCode != 200 && r.statusCode != 201) throw errorFrom(r);
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    final user = body['user'] as Map<String, dynamic>;
    return Account(
      serverUrl: server,
      token: body['token'] as String,
      email: user['email'] as String,
      userId: user['id'] as String,
    );
  }

  /// Best effort: the local sign-out happens even if the server can't be
  /// reached.
  Future<void> signOut(Account account) async {
    try {
      await client.post(
        Uri.parse('${account.serverUrl}/v1/auth/logout'),
        headers: {'Authorization': 'Bearer ${account.token}'},
      ).timeout(const Duration(seconds: 10));
    } catch (_) {}
  }
}
