import 'package:flutter/material.dart';

import '../models/recipe.dart';
import '../services/api_client.dart';
import '../widgets/recipe_card.dart';
import '../widgets/state_views.dart';
import 'recipe_detail_screen.dart';

class FavoritesScreen extends StatefulWidget {
  final ApiClient api;

  const FavoritesScreen({super.key, required this.api});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final _scrollController = ScrollController();
  final List<Recipe> _recipes = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _page = 1;
    });
    try {
      final result = await widget.api.fetchFavorites(page: 1, pageSize: 20);
      if (!mounted) return;
      setState(() {
        _recipes
          ..clear()
          ..addAll(result.$1);
        _hasMore = result.$2;
        _page = 1;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '加载失败，请下拉重试');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading) return;
    setState(() => _loadingMore = true);
    try {
      final result = await widget.api
          .fetchFavorites(page: _page + 1, pageSize: 20);
      if (!mounted) return;
      setState(() {
        _recipes.addAll(result.$1);
        _hasMore = result.$2;
        _page += 1;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _hasMore = false);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _openDetail(Recipe recipe) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            RecipeDetailScreen(api: widget.api, recipeId: recipe.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的收藏')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const LoadingState(message: '加载中...');
    }
    if (_error != null && _recipes.isEmpty) {
      return EmptyState(
        icon: Icons.error_outline,
        title: _error!,
        action: FilledButton(onPressed: _load, child: const Text('重试')),
      );
    }
    if (_recipes.isEmpty) {
      return const EmptyState(
        icon: Icons.favorite_border,
        title: '还没有收藏',
        subtitle: '在菜谱卡片或详情页点爱心即可收藏',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.68,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final recipe = _recipes[index];
                  return RecipeCard(
                    recipe: recipe,
                    api: widget.api,
                    onTap: () => _openDetail(recipe),
                    onFavoriteChanged: (now) {
                      if (!now) {
                        setState(() => _recipes.removeWhere(
                            (r) => r.id == recipe.id));
                      }
                    },
                  );
                },
                childCount: _recipes.length,
              ),
            ),
          ),
          if (_loadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}
