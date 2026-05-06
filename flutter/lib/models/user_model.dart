import 'dart:async';
import 'dart:convert';

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/hbbs/hbbs.dart';
import 'package:flutter_hbb/models/ab_model.dart';
import 'package:get/get.dart';

import '../common.dart';
import '../utils/http_service.dart' as http;
import '../utils/websocket_service.dart';
import 'model.dart';
import 'platform_model.dart';

Future<void> saveToken(String token) async {
  await bind.mainSetLocalOption(key: 'access_token', value: token);
}

Future<String?> getToken() async {
  final token = bind.mainGetLocalOption(key: 'access_token');
  return token.isEmpty ? null : token;
}

Future<void> removeToken() async {
  await bind.mainSetLocalOption(key: 'access_token', value: '');
}

bool refreshingUser = false;

class UserModel {
  final RxString userName = ''.obs;
  final RxString displayName = ''.obs;
  final RxString email = ''.obs;
  final RxString avatar = ''.obs;
  final RxBool isAdmin = false.obs;
  final RxString networkError = ''.obs;
  bool get isLogin => userName.isNotEmpty;
  String get displayNameOrUserName =>
      displayName.value.trim().isEmpty ? userName.value : displayName.value;
  String get accountLabelWithHandle {
    final username = userName.value.trim();
    if (username.isEmpty) {
      return '';
    }
    final preferred = displayName.value.trim();
    if (preferred.isEmpty || preferred == username) {
      return username;
    }
    return '$preferred (@$username)';
  }

  WeakReference<FFI> parent;

  UserModel(this.parent) {
    userName.listen((p0) {
      // When user name becomes empty, show login button
      // When user name becomes non-empty:
      //  For _updateLocalUserInfo, network error will be set later
      //  For login success, should clear network error
      networkError.value = '';
    });
  }

  Map<String, String> _apiHeaders({bool withAuth = false}) {
    final headers = <String, String>{'Accept-Language': localeName};
    if (withAuth) {
      headers['Authorization'] =
          'Bearer ${bind.mainGetLocalOption(key: 'access_token')}';
    }
    return headers;
  }

  String _trimTrailingSlash(String value) {
    var res = value.trim();
    while (res.endsWith('/')) {
      res = res.substring(0, res.length - 1);
    }
    return res;
  }

  List<String> _buildApiUrls(String base, String path,
      {String? legacyPath}) {
    final cleanBase = _trimTrailingSlash(base);
    final urls = <String>[];
    void add(String url) {
      if (url.isNotEmpty && !urls.contains(url)) {
        urls.add(url);
      }
    }

    add('$cleanBase$path');
    if (cleanBase.endsWith('/api')) {
      final withoutApi = cleanBase.substring(0, cleanBase.length - 4);
      add('$withoutApi$path');
      if (legacyPath != null) {
        add('$withoutApi$legacyPath');
      }
    } else {
      add('$cleanBase/api$path');
      if (legacyPath != null) {
        add('$cleanBase$legacyPath');
      }
    }

    return urls;
  }

  Future<void> refreshCurrentUser() async {
    if (bind.isDisableAccount()) return;
    networkError.value = '';
    final token = await getToken() ?? '';
    if (token == '') {
      await updateOtherModels();
      return;
    }
    _updateLocalUserInfo();
    if (userName.isNotEmpty) {
      final ctx = globalKey.currentContext;
      if (ctx != null) {
        WebSocketService().connect(userName.value, ctx);
      }
    }
    final baseUrl = await bind.mainGetApiServer();
    final body = {
      'id': await bind.mainGetMyId(),
      'uuid': await bind.mainGetUuid()
    };
    if (refreshingUser) return;
    try {
      refreshingUser = true;
      final urls = _buildApiUrls(baseUrl, '/current-user',
          legacyPath: '/api/currentUser');
      http.Response? response;
      String? raw;
      RequestException? lastError;
      for (final candidate in urls) {
        try {
          final r = await http.post(Uri.parse(candidate),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
                'Accept-Language': localeName,
              },
              body: json.encode(body));
          final rRaw = decode_http_response(r);
          final isHtml = rRaw.trimLeft().startsWith('<');
          if (r.statusCode == 404 || isHtml) {
            lastError = RequestException(
                r.statusCode,
                isHtml
                    ? 'Unexpected HTML response from API'
                    : 'HTTP 404');
            continue;
          }
          response = r;
          raw = rRaw;
          break;
        } catch (e) {
          lastError = RequestException(0, e.toString());
        }
      }
      if (response == null || raw == null) {
        if (lastError != null) {
          throw lastError;
        }
        throw RequestException(0, 'No API response');
      }
      refreshingUser = false;
      final status = response.statusCode;
      if (status == 401 || status == 400) {
        reset(resetOther: status == 401);
        return;
      }
      final data = json.decode(raw);
      final error = data['error'];
      if (error != null) {
        throw error;
      }

      final user = UserPayload.fromJson(data);
      _parseAndUpdateUser(user);
    } catch (e) {
      networkError.value = e.toString();
      debugPrint('Failed to refreshCurrentUser: $e');
    } finally {
      refreshingUser = false;
      await updateOtherModels();
    }
  }

  static Map<String, dynamic>? getLocalUserInfo() {
    final userInfo = bind.mainGetLocalOption(key: 'user_info');
    if (userInfo == '') {
      return null;
    }
    try {
      return json.decode(userInfo);
    } catch (e) {
      debugPrint('Failed to get local user info "$userInfo": $e');
    }
    return null;
  }

  _updateLocalUserInfo() {
    final userInfo = getLocalUserInfo();
    if (userInfo != null) {
      userName.value = (userInfo['name'] ?? '').toString();
      displayName.value = (userInfo['display_name'] ?? '').toString();
      email.value = (userInfo['email'] ?? '').toString();
      avatar.value = (userInfo['avatar'] ?? '').toString();
    }
  }

  Future<void> reset({bool resetOther = false}) async {
    await removeToken();
    await bind.mainSetLocalOption(key: 'user_info', value: '');
    WebSocketService().disconnect();
    if (resetOther) {
      await gFFI.abModel.reset();
      await gFFI.groupModel.reset();
    }
    userName.value = '';
    displayName.value = '';
    email.value = '';
    avatar.value = '';
  }

  _parseAndUpdateUser(UserPayload user) {
    userName.value = user.name;
    displayName.value = user.displayName;
    email.value = user.email;
    avatar.value = user.avatar;
    isAdmin.value = user.isAdmin;
    bind.mainSetLocalOption(key: 'user_info', value: jsonEncode(user));
    if (isWeb) {
      // ugly here, tmp solution
      bind.mainSetLocalOption(key: 'verifier', value: user.verifier ?? '');
    }
  }

  // update ab and group status
  static Future<void> updateOtherModels() async {
    await Future.wait([
      gFFI.abModel.pullAb(force: ForcePullAb.listAndCurrent, quiet: false),
      gFFI.groupModel.pull()
    ]);
  }

  Future<void> logOut({String? apiServer}) async {
    final tag = gFFI.dialogManager.showLoading(translate('Waiting'));
    try {
      final url = apiServer ?? await bind.mainGetApiServer();
        final authHeaders = getHttpHeaders();
        authHeaders['Content-Type'] = 'application/json';
        authHeaders['Accept-Language'] = localeName;
      await http
          .post(Uri.parse('$url/logout'),
              body: jsonEncode({
                'id': await bind.mainGetMyId(),
                'uuid': await bind.mainGetUuid(),
              }),
              headers: authHeaders)
          .timeout(Duration(seconds: 2));
    } catch (e) {
      debugPrint("request /api/logout failed: err=$e");
    } finally {
      await reset(resetOther: true);
      gFFI.dialogManager.dismissByTag(tag);
    }
  }

  /// throw [RequestException]
  Future<LoginResponse> login(LoginRequest loginRequest,
      {BuildContext? context}) async {
    final baseUrl = await bind.mainGetApiServer();
    final urls = _buildApiUrls(baseUrl, '/login', legacyPath: '/api/login');
    http.Response? resp;
    String? raw;
    RequestException? lastError;
    for (final loginUrl in urls) {
      final r = await http.post(Uri.parse(loginUrl),
          headers: {
            'Content-Type': 'application/json',
            'Accept-Language': localeName,
          },
          body: jsonEncode(loginRequest.toJson()));
      final rRaw = decode_http_response(r);
      final isHtml = rRaw.trimLeft().startsWith('<');
      if (r.statusCode == 404 || isHtml) {
        lastError = RequestException(
            r.statusCode,
            isHtml
                ? 'Unexpected HTML response from API'
                : 'HTTP 404');
        continue;
      }
      resp = r;
      raw = rRaw;
      break;
    }
    if (resp == null || raw == null) {
      if (lastError != null) {
        throw lastError;
      }
      throw RequestException(0, 'No API response');
    }

    final Map<String, dynamic> body;
    try {
      if (raw.trimLeft().startsWith('<')) {
        throw RequestException(
            resp.statusCode, 'Unexpected HTML response from API');
      }
      body = jsonDecode(raw);
    } catch (e) {
      debugPrint("login: jsonDecode resp body failed: ${e.toString()}");
      if (resp.statusCode != 200) {
        BotToast.showText(
            contentColor: Colors.red, text: 'HTTP ${resp.statusCode}');
      }
      if (e is RequestException) {
        rethrow;
      }
      throw RequestException(resp.statusCode, 'Invalid response from API');
    }
    if (resp.statusCode != 200) {
      throw RequestException(resp.statusCode, body['error'] ?? '');
    }
    if (body['error'] != null) {
      throw RequestException(0, body['error']);
    }

    final loginResponse = getLoginResponseFromAuthBody(body);
    if (loginResponse.access_token != null) {
      await saveToken(loginResponse.access_token!);
      if (loginResponse.user != null && context != null) {
        WebSocketService().connect(loginResponse.user!.name, context);
      }
    }
    return loginResponse;
  }

  LoginResponse getLoginResponseFromAuthBody(Map<String, dynamic> body) {
    final LoginResponse loginResponse;
    try {
      loginResponse = LoginResponse.fromJson(body);
    } catch (e) {
      debugPrint("login: jsonDecode LoginResponse failed: ${e.toString()}");
      rethrow;
    }

    final isLogInDone = loginResponse.type == HttpType.kAuthResTypeToken &&
        loginResponse.access_token != null;
    if (isLogInDone && loginResponse.user != null) {
      _parseAndUpdateUser(loginResponse.user!);
    }

    return loginResponse;
  }

  static Future<List<dynamic>> queryOidcLoginOptions() async {
    try {
      final url = await bind.mainGetApiServer();
      if (url.trim().isEmpty) return [];
      final resp = await http.get(Uri.parse('$url/login-options'), headers: {
        'Accept-Language': localeName,
      });
      final List<String> ops = [];
      for (final item in jsonDecode(resp.body)) {
        ops.add(item as String);
      }
      for (final item in ops) {
        if (item.startsWith('common-oidc/')) {
          return jsonDecode(item.substring('common-oidc/'.length));
        }
      }
      return ops
          .where((item) => item.startsWith('oidc/'))
          .map((item) => {'name': item.substring('oidc/'.length)})
          .toList();
    } catch (e) {
      debugPrint(
          "queryOidcLoginOptions: jsonDecode resp body failed: ${e.toString()}");
      return [];
    }
  }
}
