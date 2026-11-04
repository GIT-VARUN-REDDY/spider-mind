import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.status, this.message, {this.code});
  final int status; // 0 = no connection
  final String message;
  final String? code;
  bool get offline => status == 0;
  @override
  String toString() => message;
}

class AuthTokens {
  const AuthTokens(this.access, this.refresh);
  final String access;
  final String refresh;
}

/// Small JSON client: bearer token, one automatic refresh on 401 (single
/// flight), X-Client-Id on every call so realtime echoes can be ignored.
class ApiClient {
  ApiClient({required this.baseUrl, required this.clientId});

  String baseUrl;
  final String clientId;
  String? access;
  String? refresh;

  /// Called whenever tokens rotate (persist them) or become invalid (null).
  void Function(AuthTokens? tokens)? onTokens;
  final http.Client _http = http.Client();
  Future<bool>? _refreshing;

  Uri _uri(String path, [Map<String, String>? q]) {
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return Uri.parse('$base/api/v1$path').replace(queryParameters: q == null || q.isEmpty ? null : q);
  }

  Future<dynamic> call(String method, String path,
      {Object? body, Map<String, String>? query, bool auth = true, bool retry = true}) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'X-Client-Id': clientId,
      if (auth && access != null) 'Authorization': 'Bearer $access',
    };
    http.Response res;
    try {
      final req = http.Request(method, _uri(path, query))..headers.addAll(headers);
      if (body != null) req.body = jsonEncode(body);
      res = await http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 20)));

      // Transparently follow HTTP redirects (e.g. Render HTTP->HTTPS 307 redirect)
      if ((res.statusCode == 301 || res.statusCode == 302 || res.statusCode == 307 || res.statusCode == 308) &&
          res.headers.containsKey('location')) {
        final loc = res.headers['location']!;
        final redirectUri = Uri.parse(loc).isAbsolute ? Uri.parse(loc) : _uri(loc);
        final redirectReq = http.Request(method, redirectUri)..headers.addAll(headers);
        if (body != null) redirectReq.body = jsonEncode(body);
        res = await http.Response.fromStream(await _http.send(redirectReq).timeout(const Duration(seconds: 20)));
      }
    } on TimeoutException {
      throw ApiException(0, 'The server took too long to answer.');
    } catch (_) {
      throw ApiException(0, 'No connection to the server.');
    }
    if (res.statusCode == 401 && auth && retry && refresh != null) {
      if (await _refresh()) return call(method, path, body: body, query: query, auth: auth, retry: false);
    }
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (res.body.isEmpty) return null;
      try {
        return jsonDecode(res.body);
      } catch (_) {
        return null;
      }
    }
    var message = 'Something went wrong (${res.statusCode}).';
    String? code;
    try {
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final e = j['error'] as Map<String, dynamic>?;
      message = (e?['message'] as String?) ?? message;
      code = e?['code'] as String?;
    } catch (_) {}
    throw ApiException(res.statusCode, message, code: code);
  }

  Future<bool> _refresh() => _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  /// Returns true when new tokens were obtained. Only a 401 from the refresh
  /// endpoint signs the user out; a network failure keeps the session.
  Future<bool> _doRefresh() async {
    try {
      final j = await call('POST', '/auth/refresh', body: {'refreshToken': refresh}, auth: false) as Map<String, dynamic>;
      access = j['accessToken'] as String;
      refresh = j['refreshToken'] as String;
      onTokens?.call(AuthTokens(access!, refresh!));
      return true;
    } on ApiException catch (e) {
      if (e.status == 401) {
        access = null;
        refresh = null;
        onTokens?.call(null);
      }
      return false;
    }
  }

  /// Makes sure [access] is fresh before opening a socket.
  Future<bool> ensureFresh() async => refresh != null && await _refresh();

  void setTokens(AuthTokens t) {
    access = t.access;
    refresh = t.refresh;
    onTokens?.call(t);
  }

  void clear() {
    access = null;
    refresh = null;
  }
}
