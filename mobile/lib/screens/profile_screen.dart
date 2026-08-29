import 'package:flutter/material.dart';

import '../models/user.dart';
import '../services/api_client.dart';
import '../services/auth_storage.dart';
import '../theme/app_theme.dart';
import '../widgets/state_views.dart';
import '../widgets/user_avatar.dart';
import 'about_screen.dart';

class ProfileScreen extends StatefulWidget {
  final ApiClient api;
  final AuthStorage storage;
  final VoidCallback onLogout;

  const ProfileScreen({
    super.key,
    required this.api,
    required this.storage,
    required this.onLogout,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Profile? _profile;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await widget.api.getProfile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '加载失败，请重试';
        _loading = false;
      });
    }
  }

  Future<void> _editNickname() async {
    final controller = TextEditingController(
      text: _profile?.displayName ?? '',
    );
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('修改昵称'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入新的昵称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty || !mounted) return;
    try {
      await widget.api.updateProfile(
        displayName: result,
        avatar: _profile?.avatar,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('昵称已更新')));
      _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('保存失败，请重试')));
    }
  }

  Future<void> _editCarouselType() async {
    const options = {
      'most_cooked': '常做的菜',
      'recent': '最近添加',
      'random': '随机推荐',
    };
    final current = _profile?.carouselType ?? 'most_cooked';
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('首页轮播来源'),
        children: options.entries.map((entry) {
          return SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(entry.key),
            child: Row(
              children: [
                Icon(
                  current == entry.key
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: current == entry.key
                      ? AppColors.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Text(entry.value),
              ],
            ),
          );
        }).toList(),
      ),
    );
    if (selected == null || selected == current || !mounted) return;
    try {
      await widget.api.updateProfile(
        displayName: _profile?.displayName ?? _profile?.nickname ?? '',
        avatar: _profile?.avatar,
        carouselType: selected,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('轮播偏好已更新')));
      _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('保存失败，请重试')));
    }
  }

  Future<void> _editCarouselLimit() async {
    final controller =
        TextEditingController(text: '${_profile?.carouselLimit ?? 10}');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('轮播数量'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: '例如 10'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    final limit = int.tryParse(result ?? '');
    if (limit == null || limit <= 0 || !mounted) return;
    try {
      await widget.api.updateProfile(
        displayName: _profile?.displayName ?? _profile?.nickname ?? '',
        avatar: _profile?.avatar,
        carouselLimit: limit,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('轮播数量已更新')));
      _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('保存失败，请重试')));
    }
  }

  Future<void> _changePassword() async {
    final oldController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('修改密码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: oldController,
              obscureText: true,
              decoration: const InputDecoration(labelText: '当前密码'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: newController,
              obscureText: true,
              decoration: const InputDecoration(labelText: '新密码'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmController,
              obscureText: true,
              decoration: const InputDecoration(labelText: '确认新密码'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认修改'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final oldPwd = oldController.text;
    final newPwd = newController.text;
    if (newPwd.length < 6) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('新密码至少 6 位')));
      return;
    }
    if (newPwd != confirmController.text) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('两次输入的新密码不一致')));
      return;
    }
    try {
      await widget.api.changePassword(
        oldPassword: oldPwd,
        newPassword: newPwd,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('密码已修改')));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('修改失败，请重试')));
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定要退出当前账号吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await widget.storage.clear();
    widget.api.setToken(null);
    widget.onLogout();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final theme = Theme.of(context);
    if (_loading) {
      return const LoadingState(message: '加载中...');
    }
    if (_error != null) {
      return EmptyState(
        icon: Icons.error_outline,
        title: _error!,
        action: FilledButton(onPressed: _load, child: const Text('重试')),
      );
    }
    final profile = _profile!;
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              UserAvatar(
                url: widget.api.resolveMediaUrl(profile.avatar),
                name: profile.nickname,
                size: 80,
              ),
              const SizedBox(height: 12),
              Text(
                profile.nickname,
                style: AppTypography.h2.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '@${profile.username}',
                style: AppTypography.caption.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (profile.isAdmin) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withAlpha(40),
                    borderRadius: BorderRadius.circular(AppRadius.small),
                  ),
                  child: Text(
                    '管理员',
                    style: AppTypography.tag.copyWith(color: AppColors.warning),
                  ),
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.badge_outlined),
          title: const Text('修改昵称'),
          subtitle: Text(profile.displayName ?? '未设置'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _editNickname,
        ),
        ListTile(
          leading: const Icon(Icons.view_carousel_outlined),
          title: const Text('首页轮播来源'),
          subtitle: Text(_carouselTypeLabel(profile.carouselType)),
          trailing: const Icon(Icons.chevron_right),
          onTap: _editCarouselType,
        ),
        ListTile(
          leading: const Icon(Icons.filter_9_plus_outlined),
          title: const Text('首页轮播数量'),
          subtitle: Text('${profile.carouselLimit} 张'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _editCarouselLimit,
        ),
        ListTile(
          leading: const Icon(Icons.lock_outline),
          title: const Text('修改密码'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _changePassword,
        ),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('关于'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => AboutScreen(api: widget.api)),
            );
          },
        ),
        const Divider(height: 1),
        ListTile(
          leading: Icon(Icons.logout, color: theme.colorScheme.error),
          title: Text(
            '退出登录',
            style: TextStyle(color: theme.colorScheme.error),
          ),
          onTap: _logout,
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  String _carouselTypeLabel(String type) {
    switch (type) {
      case 'most_cooked':
        return '常做的菜';
      case 'recent':
        return '最近添加';
      case 'random':
        return '随机推荐';
      default:
        return type;
    }
  }
}
