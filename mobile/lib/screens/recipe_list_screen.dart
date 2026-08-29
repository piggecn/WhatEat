import 'package:flutter/material.dart';

import '../models/recipe.dart';
import '../services/api_client.dart';
import '../services/auth_storage.dart';

class RecipeListScreen extends StatefulWidget {
  final ApiClient api;
  final AuthStorage storage;
  final VoidCallback onLogout;

  const RecipeListScreen({
    super.key,
    required this.api,
    required this.storage,
    required this.onLogout,
  });

  @override
  State<RecipeListScreen> createState() => _RecipeListScreenState();
}

class _RecipeListScreenState extends State<RecipeListScreen> {
  final _recipes = <Recipe>[];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _page = 1;
    });
    try {
      final result = await widget.api.fetchRecipes(page: 1, limit: 50);
      if (!mounted) return;
      setState(() {
        _recipes
          ..clear()
          ..addAll(result.$1);
        _hasMore = result.$2;
        _page = 1;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = '加载失败，请下拉重试');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading) return;
    setState(() => _loadingMore = true);
    try {
      final result =
          await widget.api.fetchRecipes(page: _page + 1, limit: 50);
      if (!mounted) return;
      setState(() {
        _recipes.addAll(result.$1);
        _hasMore = result.$2;
        _page += 1;
      });
    } catch (_) {
      setState(() => _hasMore = false);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _logout() async {
    await widget.storage.clear();
    widget.api.setToken(null);
    if (!mounted) return;
    widget.onLogout();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('今天吃点啥'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: '退出登录',
            onPressed: _logout,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _recipes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_recipes.isEmpty) {
      return const Center(child: Text('还没有菜谱'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _recipes.length + (_hasMore ? 1 : 0),
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          if (index >= _recipes.length) {
            _loadMore();
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return _RecipeTile(recipe: _recipes[index]);
        },
      ),
    );
  }
}

class _RecipeTile extends StatelessWidget {
  final Recipe recipe;

  const _RecipeTile({required this.recipe});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 56,
          height: 56,
          child: recipe.imageUrl != null
              ? Image.network(
                  recipe.imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const _ImagePlaceholder(),
                )
              : const _ImagePlaceholder(),
        ),
      ),
      title: Text(
        recipe.title,
        style: const TextStyle(fontWeight: FontWeight.w600),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (recipe.category != null) ...[
            const SizedBox(height: 2),
            Text(recipe.category!),
          ],
          if (recipe.description != null &&
              recipe.description!.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              recipe.description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
          if (recipe.prepTime != null || recipe.cookTime != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.schedule, size: 14),
                const SizedBox(width: 4),
                Text(
                  _formatTime(recipe.prepTime, recipe.cookTime),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ],
      ),
      trailing: recipe.isFavorite
          ? Icon(Icons.favorite, color: theme.colorScheme.primary, size: 20)
          : null,
    );
  }

  String _formatTime(int? prep, int? cook) {
    final parts = <String>[];
    if (prep != null) parts.add('备 $prep 分钟');
    if (cook != null) parts.add('做 $cook 分钟');
    return parts.isEmpty ? '' : parts.join(' · ');
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.restaurant, size: 28),
    );
  }
}
