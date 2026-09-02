import 'package:flutter/material.dart';

import '../models/recipe.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../widgets/fr_tag.dart';
import '../widgets/recipe_image.dart';
import '../widgets/state_views.dart';
import '../widgets/user_avatar.dart';
import 'cook_mode_screen.dart';
import 'recipe_edit_screen.dart';

class RecipeDetailScreen extends StatefulWidget {
  final ApiClient api;
  final int recipeId;

  const RecipeDetailScreen({
    super.key,
    required this.api,
    required this.recipeId,
  });

  @override
  State<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends State<RecipeDetailScreen> {
  Recipe? _recipe;
  bool _loading = true;
  String? _error;
  bool _favorite = false;
  bool _togglingFavorite = false;
  int? _currentUserId;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadMe();
  }

  Future<void> _loadMe() async {
    try {
      final user = await widget.api.me();
      if (!mounted) return;
      setState(() {
        _currentUserId = user.id;
        _isAdmin = user.isAdmin;
      });
    } catch (_) {
      // 获取当前用户失败时保持只读
    }
  }

  bool get _canEdit {
    final recipe = _recipe;
    if (recipe == null || recipe.createdBy == null) return false;
    return _isAdmin || recipe.createdBy == _currentUserId;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final recipe = await widget.api.fetchRecipeDetail(widget.recipeId);
      if (!mounted) return;
      setState(() {
        _recipe = recipe;
        _favorite = recipe.isFavorite;
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

  Future<void> _openEdit() async {
    final recipe = _recipe;
    if (recipe == null) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RecipeEditScreen(api: widget.api, recipe: recipe),
      ),
    );
    if (saved == true && mounted) {
      _load();
    }
  }

  Future<void> _deleteRecipe() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除菜谱'),
          content: const Text('删除后无法恢复，确定要删除这道菜谱吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
              ),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.api.deleteRecipe(widget.recipeId);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('删除失败，请重试')));
    }
  }

  Future<void> _toggleFavorite() async {
    if (_togglingFavorite) return;
    setState(() => _togglingFavorite = true);
    try {
      final now = await widget.api.toggleFavorite(widget.recipeId);
      if (!mounted) return;
      setState(() {
        _favorite = now;
        _togglingFavorite = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(now ? '已加入收藏' : '已取消收藏')));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _togglingFavorite = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _togglingFavorite = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('操作失败，请重试')));
    }
  }

  Future<void> _checkIn() async {
    final mealType = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '选择用餐时间打卡',
                  style: AppTypography.h3.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.wb_sunny_outlined),
                title: const Text('早餐'),
                onTap: () => Navigator.of(context).pop('breakfast'),
              ),
              ListTile(
                leading: const Icon(Icons.light_mode_outlined),
                title: const Text('午餐'),
                onTap: () => Navigator.of(context).pop('lunch'),
              ),
              ListTile(
                leading: const Icon(Icons.nights_stay_outlined),
                title: const Text('晚餐'),
                onTap: () => Navigator.of(context).pop('dinner'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (mealType == null || !mounted) return;
    final now = DateTime.now();
    final date =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    try {
      await widget.api.createMeal(
        recipeId: widget.recipeId,
        mealType: mealType,
        date: date,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('打卡成功')));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('打卡失败，请重试')));
    }
  }

  String _formatTime() {
    final prep = _recipe!.prepTime;
    final cook = _recipe!.cookTime;
    final parts = <String>[];
    if (prep != null) parts.add('备 $prep 分钟');
    if (cook != null) parts.add('做 $cook 分钟');
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_recipe?.title ?? '菜谱详情'),
        actions: [
          if (_recipe != null)
            IconButton(
              tooltip: _favorite ? '取消收藏' : '收藏',
              onPressed: _togglingFavorite ? null : _toggleFavorite,
              icon: _togglingFavorite
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _favorite ? Icons.favorite : Icons.favorite_border,
                      color: _favorite ? AppColors.error : null,
                    ),
            ),
          if (_recipe != null && _canEdit)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'edit') {
                  _openEdit();
                } else if (value == 'delete') {
                  _deleteRecipe();
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('编辑'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline, color: AppColors.error),
                    title: Text('删除'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
        ],
      ),
      body: _buildBody(theme),
      bottomNavigationBar: _recipe == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: FilledButton.icon(
                  onPressed: _checkIn,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('今天吃这个 · 打卡'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const LoadingState(message: '加载菜谱中...');
    }
    if (_error != null) {
      return EmptyState(
        icon: Icons.error_outline,
        title: _error!,
        action: FilledButton(onPressed: _load, child: const Text('重试')),
      );
    }
    final recipe = _recipe!;
    final imageUrl = widget.api.resolveMediaUrl(
      recipe.imageUrl ?? recipe.imagePath,
    );
    final authorName = recipe.authorDisplayName?.isNotEmpty == true
        ? recipe.authorDisplayName!
        : recipe.author;
    final timeText = _formatTime();

    return ListView(
      children: [
        AspectRatio(
          aspectRatio: 16 / 10,
          child: RecipeImage(url: imageUrl, fit: BoxFit.cover, iconSize: 64),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                recipe.title,
                style: AppTypography.h1.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (recipe.category != null && recipe.category!.isNotEmpty)
                    FrTag(recipe.category!),
                  for (final tag in recipe.mealTags)
                    FrTag(
                      tag,
                      background: theme.colorScheme.surfaceContainerHighest,
                      foreground: theme.colorScheme.onSurfaceVariant,
                    ),
                  for (final tag in recipe.dietTags)
                    FrTag(
                      '🚫 $tag',
                      background: AppColors.error.withAlpha(24),
                      foreground: AppColors.error,
                    ),
                ],
              ),
              if (timeText.isNotEmpty || recipe.servings > 0) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (timeText.isNotEmpty) ...[
                      Icon(
                        Icons.schedule,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        timeText,
                        style: AppTypography.caption.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (timeText.isNotEmpty && recipe.servings > 0)
                      const SizedBox(width: 16),
                    if (recipe.servings > 0) ...[
                      Icon(
                        Icons.people_outline,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${recipe.servings} 人份',
                        style: AppTypography.caption.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
              if (recipe.description != null &&
                  recipe.description!.trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  recipe.description!.trim(),
                  style: AppTypography.body.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (authorName != null && authorName.isNotEmpty) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withAlpha(
                      120,
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.medium),
                  ),
                  child: Row(
                    children: [
                      UserAvatar(
                        url: widget.api.resolveMediaUrl(recipe.authorAvatar),
                        name: authorName,
                        size: 36,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '作者',
                              style: AppTypography.caption.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              authorName,
                              style: AppTypography.body.copyWith(
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (recipe.ingredients.isNotEmpty) ...[
                const SizedBox(height: 24),
                _SectionTitle(
                  title: '食材清单',
                  icon: Icons.shopping_basket_outlined,
                ),
                const SizedBox(height: 8),
                ...recipe.ingredients.map(
                  (ing) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Icon(
                            Icons.circle,
                            size: 6,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            ing.name,
                            style: AppTypography.body.copyWith(
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                        if (ing.amount != null || ing.unit != null)
                          Text(
                            [
                              ing.amount,
                              ing.unit,
                            ].where((e) => e != null && e.isNotEmpty).join(' '),
                            style: AppTypography.body.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              if (recipe.steps.isNotEmpty) ...[
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CookModeScreen(
                          api: widget.api,
                          recipeTitle: recipe.title,
                          steps: recipe.steps,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.local_fire_department_outlined),
                  label: const Text('进入烹饪模式'),
                ),
                const SizedBox(height: 16),
                const _SectionTitle(
                  title: '烹饪步骤',
                  icon: Icons.format_list_numbered,
                ),
                const SizedBox(height: 12),
                ...recipe.steps.asMap().entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(AppRadius.full),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${entry.value.stepNumber ?? entry.key + 1}',
                            style: AppTypography.tag.copyWith(
                              color: AppColors.onPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            entry.value.description,
                            style: AppTypography.body.copyWith(
                              color: theme.colorScheme.onSurface,
                              height: 1.6,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (recipe.ingredients.isEmpty && recipe.steps.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text(
                      '这道菜还没有食材和步骤',
                      style: AppTypography.body.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionTitle({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: AppTypography.h3.copyWith(color: theme.colorScheme.onSurface),
        ),
      ],
    );
  }
}
