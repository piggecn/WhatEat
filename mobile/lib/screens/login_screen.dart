import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/auth_storage.dart';
import '../services/server_config.dart';
import 'qr_scan_screen.dart';

class LoginScreen extends StatefulWidget {
  final ApiClient api;
  final AuthStorage storage;
  final ServerConfig serverConfig;
  final VoidCallback onLoggedIn;

  const LoginScreen({
    super.key,
    required this.api,
    required this.storage,
    required this.serverConfig,
    required this.onLoggedIn,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _serverController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadServer();
  }

  Future<void> _loadServer() async {
    final saved = await widget.serverConfig.readBaseUrl();
    if (saved != null && saved.isNotEmpty) {
      _serverController.text = saved;
      widget.api.setBaseUrl(saved);
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _scanQr() async {
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (raw == null || !mounted) return;
    final baseUrl = _parseQr(raw);
    if (baseUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('二维码格式不正确，请使用服务端「关于页」的配置二维码')),
      );
      return;
    }
    setState(() {
      _serverController.text = baseUrl;
      widget.api.setBaseUrl(baseUrl);
    });
  }

  String? _parseQr(String raw) {
    try {
      final data = jsonDecode(raw);
      if (data is Map<String, dynamic>) {
        final value = data['base_url'];
        if (value is String && value.trim().isNotEmpty) {
          return ApiClient.normalizeBaseUrl(value);
        }
      }
    } catch (_) {
      // 非 JSON，尝试直接当作地址
    }
    final normalized = ApiClient.normalizeBaseUrl(raw);
    return normalized.isEmpty ? null : normalized;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final baseUrl = ApiClient.normalizeBaseUrl(_serverController.text);
    if (baseUrl.isEmpty) {
      setState(() => _error = '请输入服务器地址');
      return;
    }
    widget.api.setBaseUrl(baseUrl);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.api.login(
        _usernameController.text.trim(),
        _passwordController.text,
      );
      await widget.serverConfig.saveBaseUrl(baseUrl);
      await widget.storage.saveToken(result.token);
      await widget.storage.saveUser(result.user.username);
      if (!mounted) return;
      widget.onLoggedIn();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = '无法连接服务器，请检查地址与端口是否正确');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.asset(
                      'assets/logo.png',
                      width: 96,
                      height: 96,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '今天吃点啥',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _serverController,
                    decoration: InputDecoration(
                      labelText: '服务器地址',
                      hintText: 'http://192.168.1.10:8765 或 域名:端口',
                      prefixIcon: const Icon(Icons.dns_outlined),
                      suffixIcon: IconButton(
                        tooltip: '扫描二维码配置',
                        icon: const Icon(Icons.qr_code_scanner),
                        onPressed: _loading ? null : _scanQr,
                      ),
                    ),
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.next,
                    validator: (v) => v == null || v.trim().isEmpty
                        ? '请输入服务器地址'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _usernameController,
                    decoration: const InputDecoration(
                      labelText: '用户名',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    textInputAction: TextInputAction.next,
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? '请输入用户名' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    decoration: const InputDecoration(
                      labelText: '密码',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    validator: (v) =>
                        v == null || v.isEmpty ? '请输入密码' : null,
                  ),
                  const SizedBox(height: 24),
                  if (_error != null) ...[
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    const SizedBox(height: 12),
                  ],
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('登录'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
