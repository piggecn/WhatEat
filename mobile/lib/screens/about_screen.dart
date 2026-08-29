import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_client.dart';
import '../theme/app_theme.dart';

class AboutScreen extends StatefulWidget {
  final ApiClient api;

  const AboutScreen({super.key, required this.api});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = '';
  String _buildNumber = '';

  // 版本检测状态：idle / checking / latest / update
  String _updateState = 'idle';
  String _remoteVersion = '';
  String? _remoteNotes;
  String? _apkUrl;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (!mounted) return;
      setState(() {
        _version = info.version;
        _buildNumber = info.buildNumber;
      });
    });
  }

  Future<void> _checkUpdate() async {
    if (_updateState == 'checking') return;
    setState(() => _updateState = 'checking');
    try {
      final info = await widget.api.checkApp(force: true);
      if (!mounted) return;
      if (info['configured'] != true || info['version'] == null) {
        setState(() => _updateState = 'failed');
        return;
      }
      final remote = info['version'].toString().trim();
      if (remote.isEmpty) {
        setState(() => _updateState = 'failed');
        return;
      }
      if (_version.isEmpty || _isNewerVersion(remote, _version)) {
        final assets = info['assets'];
        String? apk;
        if (assets is List) {
          for (final asset in assets) {
            if (asset is Map &&
                (asset['name'] ?? '').toString().toLowerCase().endsWith('.apk')) {
              apk = (asset['url'] ?? '').toString();
              if (apk.isNotEmpty) break;
            }
          }
        }
        setState(() {
          _updateState = 'update';
          _remoteVersion = remote;
          _remoteNotes = (info['notes'] ?? '').toString();
          _apkUrl = apk;
        });
        return;
      }
      setState(() => _updateState = 'latest');
    } catch (_) {
      if (mounted) setState(() => _updateState = 'failed');
    }
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

  Future<void> _openApk() async {
    final url = _apkUrl;
    if (url == null || url.isEmpty) return;
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('无法打开下载链接')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final versionText = _version.isEmpty
        ? '…'
        : _buildNumber.isEmpty
            ? _version
            : '$_version+$_buildNumber';
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 16),
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.large),
              child: Image.asset(
                'assets/logo.png',
                width: 88,
                height: 88,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              '今天吃点啥',
              style: AppTypography.h1.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              'WhatEat',
              style: AppTypography.caption.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 32),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('版本'),
            subtitle: Text(
              _updateState == 'update'
                  ? '有新版本 $_remoteVersion 可更新'
                  : _updateState == 'latest'
                      ? '已是最新版本'
                      : _updateState == 'checking'
                          ? '正在检测新版本…'
                          : '点按可检测新版本',
              style: AppTypography.caption.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            trailing: _updateState == 'checking'
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    versionText,
                    style: AppTypography.body.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
            onTap: _updateState == 'update'
                ? null
                : () => _checkUpdate(),
          ),
          if (_updateState == 'update') ...[
            ListTile(
              dense: true,
              leading: Icon(
                Icons.new_releases,
                color: theme.colorScheme.primary,
              ),
              title: Text(
                '发现新版本 $_remoteVersion',
                style: AppTypography.body.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              subtitle: (_remoteNotes ?? '').isNotEmpty
                  ? Text(
                      _remoteNotes!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  : null,
              isThreeLine: (_remoteNotes ?? '').isNotEmpty,
              trailing: _apkUrl != null && _apkUrl!.isNotEmpty
                  ? FilledButton(
                      onPressed: _openApk,
                      child: const Text('去更新'),
                    )
                  : null,
            ),
          ],
          if (_updateState == 'failed') ...[
            ListTile(
              dense: true,
              leading: Icon(
                Icons.error_outline,
                color: theme.colorScheme.error,
              ),
              title: Text(
                '检测失败，请检查服务器地址后重试',
                style: AppTypography.caption.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
              trailing: TextButton(
                onPressed: _checkUpdate,
                child: const Text('重试'),
              ),
            ),
          ],
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('服务器'),
            subtitle: Text(
              widget.api.baseUrl.isEmpty ? '未配置' : widget.api.baseUrl,
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              '记录每一餐，好好吃饭',
              style: AppTypography.caption.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
