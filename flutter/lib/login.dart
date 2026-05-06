import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/hbbs/hbbs.dart';
import 'package:flutter_hbb/models/user_model.dart';
import 'package:window_manager/window_manager.dart';

import 'models/platform_model.dart';

final ValueNotifier<bool> loginRequiredNotifier = ValueNotifier<bool>(false);

// Biến kiểm soát trạng thái dialog đăng nhập
bool isLoginDialogOpen = false;

void requireLogin() {
  loginRequiredNotifier.value = true;
}

void clearLoginRequired() {
  loginRequiredNotifier.value = false;
}

class LoginScreen extends StatefulWidget {
  final VoidCallback onExit;
  final VoidCallback onLoggedIn;

  const LoginScreen({
    Key? key,
    required this.onExit,
    required this.onLoggedIn,
  }) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();
  String _username = '';
  String _password = '';
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (isDesktop) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await windowManager.center();
      });
    }
  }

  Future<Map<String, String>> _getDeviceInfo() async {
    String hardwareId = '';
    String deviceName = '';
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (isWindows) {
        final winInfo = await deviceInfo.windowsInfo;
        hardwareId = winInfo.deviceId;
        deviceName = winInfo.computerName;
      } else if (isLinux) {
        final linuxInfo = await deviceInfo.linuxInfo;
        hardwareId = linuxInfo.machineId ?? linuxInfo.id;
        deviceName = linuxInfo.name ?? linuxInfo.prettyName ?? '';
      } else if (isMacOS) {
        final macInfo = await deviceInfo.macOsInfo;
        hardwareId = macInfo.systemGUID ?? '';
        deviceName = macInfo.computerName ?? '';
      } else if (isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        hardwareId = androidInfo.id;
        deviceName = androidInfo.device ?? androidInfo.model ?? '';
      } else if (isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        hardwareId = iosInfo.identifierForVendor ?? '';
        deviceName = iosInfo.name ?? '';
      }
    } catch (e) {
      debugPrint('[LoginScreen] Failed to get device info: $e');
      hardwareId = '';
      deviceName = '';
    }
    debugPrint('[LoginScreen] hardwareId: $hardwareId');
    debugPrint('[LoginScreen] deviceName: $deviceName');
    return {
      'hardwareId': hardwareId,
      'deviceName': deviceName,
    };
  }

  void _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    _formKey.currentState!.save();
    try {
      final deviceInfo = await _getDeviceInfo();
      final hardwareId = deviceInfo['hardwareId'] ?? '';
      final deviceName = deviceInfo['deviceName'] ?? '';
      debugPrint('[LoginScreen] onLogin hardwareId: $hardwareId');
      if (hardwareId.isEmpty) {
        setState(() {
          _error = 'Failed to get Hardware ID. Please check again!';
        });
        return;
      }

      final loginRequest = LoginRequest(
        username: _username,
        password: _password,
        hardwareId: hardwareId,
        deviceName: deviceName,
      );

      final loginResponse = await gFFI.userModel.login(
        loginRequest,
        context: context,
      );

      if (!mounted) return;

      debugPrint('[LoginScreen] loginResponse.user: ${loginResponse.user.toString()}');
      debugPrint('[LoginScreen] username: $_username');
      debugPrint('[LoginScreen] loginResponse.user!.name: ${loginResponse.user?.name ?? 'null'}');

      if (loginResponse.access_token != null &&
          loginResponse.user != null &&
          loginResponse.user!.name == _username) {
        // Login thành công
        clearLoginRequired();
        widget.onLoggedIn();
        return;
      } else {
        setState(() {
          _error = 'Invalid username or password!';
        });
      }
    } on RequestException catch (err) {
      if (mounted) {
        setState(() {
          _error = translate(err.cause);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = "Unknown error: $e";
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _exit() {
    widget.onExit();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            elevation: 0,
            color: theme.dialogBackgroundColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      translate('Login'),
                      style: theme.textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _usernameController,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText:
                            translate('Username'),
                      ),
                      onSaved: (v) => _username = v?.trim() ?? '',
                      validator: (v) => (v == null || v.isEmpty)
                          ? translate('Username missed')
                          : null,
                      onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                      enabled: !_loading,
                      onChanged: (_) {
                        if (_error != null) {
                          setState(() {
                            _error = null;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _passwordController,
                      focusNode: _passwordFocus,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: translate('Password'),
                      ),
                      obscureText: true,
                      onSaved: (v) => _password = v ?? '',
                      validator: (v) => (v == null || v.isEmpty)
                          ? translate('Password missed')
                          : null,
                      onFieldSubmitted: (_) {
                        if (!_loading) {
                          _submit();
                        }
                      },
                      enabled: !_loading,
                      onChanged: (_) {
                        if (_error != null) {
                          setState(() {
                            _error = null;
                          });
                        }
                      },
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!,
                          style:
                              const TextStyle(color: Colors.red, fontSize: 12)),
                    ],
                    const SizedBox(height: 16),
                    if (_loading)
                      const LinearProgressIndicator()
                    else
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          dialogButton(
                            'Cancel',
                            onPressed: _exit,
                            isOutline: true,
                          ),
                          const SizedBox(width: 8),
                          dialogButton(
                            'Login',
                            onPressed: _submit,
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
