import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'screens/paste_import_screen.dart';
import 'services/api_client.dart';
import 'services/auth_storage.dart';
import 'services/server_config.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const WhatEatApp());
}

class WhatEatApp extends StatefulWidget {
  const WhatEatApp({super.key});

  @override
  State<WhatEatApp> createState() => _WhatEatAppState();
}

class _WhatEatAppState extends State<WhatEatApp> {
  final ApiClient _api = ApiClient();
  final AuthStorage _storage = AuthStorage();
  final ServerConfig _serverConfig = ServerConfig();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  static const _shareChannel = MethodChannel('cn.piggecn.whateat/sharing');
  String? _pendingSharedText;
  bool _loading = true;
  bool _loggedIn = false;

  @override
  void initState() {
    super.initState();
    _initShareReceiver();
    _bootstrap();
  }

  @override
  void dispose() {
    _shareChannel.setMethodCallHandler(null);
    super.dispose();
  }

  void _initShareReceiver() {
    _shareChannel.setMethodCallHandler((call) async {
      if (call.method == 'onSharedText') {
        final text = (call.arguments as String?)?.trim();
        if (text != null && text.isNotEmpty) _handleSharedText(text);
      }
    });
    // 冷启动时尝试获取暂存的分享文本
    _shareChannel.invokeMethod<String>('getSharedText').then((text) {
      if (text != null && text.trim().isNotEmpty) {
        _handleSharedText(text.trim());
      }
    });
  }

  void _handleSharedText(String text) {
    if (!_loggedIn) {
      _pendingSharedText = text;
      return;
    }
    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      _pendingSharedText = text;
      return;
    }
    navigator.push(
      MaterialPageRoute(
        builder: (_) => PasteImportScreen(api: _api, initialText: text),
      ),
    );
  }

  void _flushPendingShare() {
    final text = _pendingSharedText;
    if (text == null) return;
    _pendingSharedText = null;
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleSharedText(text));
  }

  Future<void> _checkUpdate() async {
    try {
      final results = await Future.wait([
        _api.checkApp(),
        PackageInfo.fromPlatform(),
      ]);
      if (!mounted) return;
      final info = results[0] as Map<String, dynamic>;
      final packageInfo = results[1] as PackageInfo;
      if (info['configured'] != true) return;
      final remoteVersion = (info['version'] ?? '').toString();
      if (remoteVersion.isEmpty) return;
      if (!_isNewerVersion(remoteVersion, packageInfo.version)) return;
      final assets = info['assets'];
      String? apkUrl;
      if (assets is List) {
        for (final asset in assets) {
          if (asset is Map &&
              (asset['name'] ?? '').toString().toLowerCase().endsWith('.apk')) {
            apkUrl = (asset['url'] ?? '').toString();
            break;
          }
        }
      }
      final notes = (info['notes'] ?? '').toString();
      _navigatorKey.currentState?.push(
        DialogRoute(
          context: _navigatorKey.currentContext!,
          builder: (dialogContext) => AlertDialog(
            title: Text('发现新版本 $remoteVersion'),
            content: SingleChildScrollView(
              child: Text(
                notes.isEmpty ? '当前版本 ${packageInfo.version}，建议更新。' : notes,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('稍后'),
              ),
              if (apkUrl != null && apkUrl.isNotEmpty)
                FilledButton(
                  onPressed: () {
                    launchUrl(
                      Uri.parse(apkUrl!),
                      mode: LaunchMode.externalApplication,
                    );
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('去下载'),
                ),
            ],
          ),
        ),
      );
    } catch (_) {}
  }

  bool _isNewerVersion(String remote, String local) {
    List<int> parse(String v) => v
        .replaceFirst(RegExp(r'^[vV]'), '')
        .split(RegExp(r'[.-]'))
        .map((e) => int.tryParse(e) ?? 0)
        .toList();
    final r = parse(remote);
    final l = parse(local);
    final length = r.length > l.length ? r.length : l.length;
    for (var i = 0; i < length; i++) {
      final rv = i < r.length ? r[i] : 0;
      final lv = i < l.length ? l[i] : 0;
      if (rv != lv) return rv > lv;
    }
    return false;
  }

  Future<void> _bootstrap() async {
    final baseUrl = await _serverConfig.readBaseUrl();
    if (baseUrl != null && baseUrl.isNotEmpty) {
      _api.setBaseUrl(baseUrl);
    }
    final token = await _storage.readToken();
    var loggedIn = false;
    if (token != null && token.isNotEmpty) {
      _api.setToken(token);
      try {
        await _api.me();
        loggedIn = true;
      } catch (_) {
        _api.setToken(null);
        await _storage.clear();
      }
    }
    if (!mounted) return;
    setState(() {
      _loggedIn = loggedIn;
      _loading = false;
    });
    if (loggedIn) {
      _flushPendingShare();
      _checkUpdate();
    }
  }

  void _onLoggedIn() {
    setState(() => _loggedIn = true);
    _flushPendingShare();
    _checkUpdate();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '今天吃点啥',
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: _loading
          ? const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            )
          : _loggedIn
              ? HomeShell(
                  api: _api,
                  storage: _storage,
                  onLogout: () => setState(() => _loggedIn = false),
                )
              : LoginScreen(
                  api: _api,
                  storage: _storage,
                  serverConfig: _serverConfig,
                  onLoggedIn: _onLoggedIn,
                ),
    );
  }
}
