import 'package:flutter/material.dart';

import '../models/recipe.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';
import 'fr_tag.dart';
import 'recipe_image.dart';
import 'user_avatar.dart';

class RecipeCard extends StatefulWidget {
  final Recipe recipe;
  final ApiClient api;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onFavoriteChanged;

  const RecipeCard({
    super.key,
    required this.recipe,
    required this.api,
    this.onTap,
    this.onFavoriteChanged,
  });

  @override
  State<RecipeCard> createState() => _RecipeCardState();
}

class _RecipeCardState extends State<RecipeCard> {
  late bool _isFavorite;
  bool _toggling = false;

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.recipe.isFavorite;
  }

  @override
  void didUpdateWidget(covariant RecipeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recipe.id != widget.recipe.id) {
      _isFavorite = widget.recipe.isFavorite;
      _toggling = false;
    }
  }

  String get _imageUrl {
    final raw = widget.recipe.imageUrl ?? widget.recipe.imagePath;
    return widget.api.resolveMediaUrl(raw);
  }

  String get _avatarUrl =>
      widget.api.resolveMediaUrl(widget.recipe.authorAvatar);

  String? get _authorName {
    final display = widget.recipe.authorDisplayName;
    if (display != null && display.trim().isNotEmpty) return display;
    final author = widget.recipe.author;
    if (author != null && author.trim().isNotEmpty) return author;
    return null;
  }

  String? get _timeText {
    final prep = widget.recipe.prepTime;
    final cook = widget.recipe.cookTime;
    if (prep == null && cook == null) return null;
    final parts = <String>[];
    if (prep != null) parts.add('备 $prep 分钟');
    if (cook != null) parts.add('做 $cook 分钟');
    return parts.join(' · ');
  }

  Future<void> _toggleFavorite() async {
    if (_toggling) return;
    setState(() => _toggling = true);
    try {
      final now = await widget.api.toggleFavorite(widget.recipe.id);
      if (!mounted) return;
      setState(() {
        _isFavorite = now;
        _toggling = false;
      });
      widget.onFavoriteChanged?.call(now);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _toggling = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _toggling = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('操作失败，请重试')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final category = widget.recipe.category;
    final time = _timeText;
    final author = _authorName;
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(AppRadius.large),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RecipeImage(url: _imageUrl, fit: BoxFit.cover),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _buildFavoriteButton(theme),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.recipe.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.h3
                        .copyWith(color: theme.colorScheme.onSurface),
                  ),
                  if (category != null || time != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (category != null && category.isNotEmpty) ...[
                          FrTag(category),
                          if (time != null) const SizedBox(width: 8),
                        ],
                        if (time != null) ...[
                          const Spacer(),
                          Icon(
                            Icons.schedule,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            time,
                            style: AppTypography.caption.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                  if (author != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        UserAvatar(url: _avatarUrl, name: author, size: 20),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.caption.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFavoriteButton(ThemeData theme) {
    return Material(
      color: Colors.black.withAlpha(70),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _toggleFavorite,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: _toggling
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Icon(
                  _isFavorite ? Icons.favorite : Icons.favorite_border,
                  size: 18,
                  color: _isFavorite ? AppColors.error : Colors.white,
                ),
        ),
      ),
    );
  }
}
