import 'package:flutter/material.dart';

import '../models/recipe_draft.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../widgets/recipe_image.dart';
import '../widgets/state_views.dart';
import 'recipe_edit_screen.dart';

class OnlineRecipeScreen extends StatefulWidget {
  final ApiClient api;

  const OnlineRecipeScreen({super.key, required this.api});

  @override
  State<OnlineRecipeScreen> createState() => _OnlineRecipeScreenState();
}

class _OnlineRecipeScreenState extends State<OnlineRecipeScreen> {
  final _controller = TextEditingController();
  bool _loading = false;
  bool _searched = false;
  String? _error;
  String _zhKeyword = '';
  List<Map<String, dynamic>> _results = [];
  int _preparingIndex = -1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final keyword = _controller.text.trim();
    if (keyword.isEmpty) return;
    setState(() {
      _loading = true;
      _searched = false;
      _error = null;
      _results = [];
      _zhKeyword = '';
    });
    try {
      final (items, _, zhKeyword) = await widget.api.searchOnlineRecipe(keyword);
      if (!mounted) return;
      setState(() {
        _results = items;
        _zhKeyword = zhKeyword;
        _searched = true;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _searched = true;
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _searched = true;
        _loading = false;
        _error = '搜索失败，请检查服务器配置';
      });
    }
  }

  Future<void> _import(int index) async {
    if (_preparingIndex >= 0) return;
    final item = _results[index];
    setState(() => _preparingIndex = index);
    try {
      final prepared = await widget.api.prepareOnlineRecipe({
        'id': item['id'],
        'title': item['title'],
        'category': item['category'],
        'area': item['area'],
        'thumb': item['thumb'],
        'ingredients': item['ingredients'] ?? const [],
        'steps': item['steps'] ?? const [],
      });
      if (!mounted) return;
      final draft = RecipeDraft.fromPrepare(prepared);
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => RecipeEditScreen(api: widget.api, draft: draft),
        ),
      );
      if (!mounted) return;
      setState(() => _preparingIndex = -1);
      if (saved == true) {
        Navigator.of(context).pop(true);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _preparingIndex = -1);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _preparingIndex = -1);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('导入失败，请重试')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('在线食谱导入')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TextField(
                controller: _controller,
                onSubmitted: (_) => _search(),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: '输入菜名，例如 红烧肉 / Mapo Tofu',
                  prefixIcon: const Icon(Icons.travel_explore),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: _search,
                  ),
                ),
              ),
            ),
            if (_zhKeyword.isNotEmpty && _zhKeyword != _controller.text.trim())
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '已按「$_zhKeyword」检索',
                    style: AppTypography.caption.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const LoadingState(message: '搜索中，可能需要几秒钟...');
    }
    if (_error != null) {
      return EmptyState(
        icon: Icons.error_outline,
        title: _error!,
        action: FilledButton(
          onPressed: _search,
          child: const Text('重试'),
        ),
      );
    }
    if (_results.isEmpty) {
      return _searched
          ? const EmptyState(
              icon: Icons.search_off,
              title: '没有找到相关食谱',
              subtitle: '换个关键词试试，支持中英文菜名',
            )
          : const EmptyState(
              icon: Icons.travel_explore,
              title: '搜索在线食谱库',
              subtitle: '选中后可一键导入为本地菜谱，支持英转中',
            );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: _results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) => _buildItem(index),
    );
  }

  Widget _buildItem(int index) {
    final theme = Theme.of(context);
    final item = _results[index];
    final title = (item['title'] ?? '').toString();
    final category = (item['category'] ?? '').toString();
    final area = (item['area'] ?? '').toString();
    final thumb = widget.api.resolveMediaUrl(item['thumb']);
    final preparing = _preparingIndex == index;

    final subtitleParts = <String>[
      if (category.isNotEmpty) category,
      if (area.isNotEmpty) area,
    ];

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: preparing ? null : () => _import(index),
        child: Row(
          children: [
            SizedBox(
              width: 96,
              height: 96,
              child: thumb.isEmpty
                  ? const RecipeImagePlaceholder(iconSize: 32)
                  : RecipeImage(url: thumb, fit: BoxFit.cover, iconSize: 32),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.h3.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    if (subtitleParts.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitleParts.join(' · '),
                        style: AppTypography.caption.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: preparing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      Icons.download_outlined,
                      color: theme.colorScheme.primary,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
