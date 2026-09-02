import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../widgets/state_views.dart';

class OnlineImageSearchScreen extends StatefulWidget {
  final ApiClient api;
  final String keyword;

  const OnlineImageSearchScreen({
    super.key,
    required this.api,
    this.keyword = '',
  });

  @override
  State<OnlineImageSearchScreen> createState() =>
      _OnlineImageSearchScreenState();
}

class _OnlineImageSearchScreenState extends State<OnlineImageSearchScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _loading = false;
  bool _searched = false;
  bool _loadingMore = false;
  String? _error;
  List<Map<String, dynamic>> _results = [];
  int _page = 0;
  String _keyword = '';
  String _provider = 'pixabay';
  static const _perPage = 12;

  static const _providers = {
    'pixabay': 'Pixabay',
    'pixabay_zh': 'Pixabay 中文',
    'wikimedia': 'Wikimedia',
  };

  @override
  void initState() {
    super.initState();
    final keyword = widget.keyword.trim();
    _keyword = keyword;
    _controller.text = keyword;
    _scrollController.addListener(_onScroll);
    if (keyword.isNotEmpty) _search();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final keyword = _controller.text.trim();
    if (keyword.isEmpty) return;
    setState(() {
      _loading = true;
      _searched = false;
      _error = null;
      _keyword = keyword;
      _results = [];
      _page = 0;
    });
    try {
      final results = await widget.api.searchImage(
        keyword: keyword,
        page: 1,
        perPage: _perPage,
        provider: _provider,
      );
      if (!mounted) return;
      setState(() {
        _results = results;
        _page = 1;
        _searched = true;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _searched = true;
        _loading = false;
        _error = '图片搜索失败，请检查服务器配置';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || _keyword.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final next = await widget.api.searchImage(
        keyword: _keyword,
        page: _page + 1,
        perPage: _perPage,
        provider: _provider,
      );
      if (!mounted) return;
      setState(() {
        _results.addAll(next);
        _page += 1;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('在线配图')),
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
                  hintText: '输入菜名，例如 番茄炒蛋',
                  prefixIcon: const Icon(Icons.photo_library_outlined),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: _search,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Text('渠道：',
                      style: AppTypography.caption.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      )),
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      children: [
                        for (final entry in _providers.entries)
                          ChoiceChip(
                            label: Text(entry.value),
                            selected: _provider == entry.key,
                            onSelected: (_) {
                              setState(() => _provider = entry.key);
                              if (_controller.text.trim().isNotEmpty) {
                                _search();
                              }
                            },
                          ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _pickManualUrl,
                    icon: const Icon(Icons.edit_location_alt_outlined,
                        size: 16),
                    label: const Text('手动输链接'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const LoadingState(message: '搜索中...')
                  : _error != null
                      ? EmptyState(
                          icon: Icons.error_outline,
                          title: _error!,
                          action: FilledButton(
                            onPressed: _search,
                            child: const Text('重试'),
                          ),
                        )
                      : _results.isEmpty
                          ? _searched
                              ? const EmptyState(
                                  icon: Icons.photo_library_outlined,
                                  title: '没有找到合适的图片',
                                  subtitle: '换个关键词试试，或改用拍照/相册',
                                )
                              : const EmptyState(
                                  icon: Icons.image_search,
                                  title: '输入菜名搜索图片',
                                  subtitle: '点击任意图片即可设为封面',
                                )
                          : _buildGrid(),
            ),
            if (_loadingMore)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickManualUrl() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('手动输入图片链接'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
              hintText: 'https://...（jpg/png/webp）'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('使用'),
          ),
        ],
      ),
    );
    if (url != null && url.startsWith('http') && mounted) {
      Navigator.of(context).pop(url);
    }
  }

  Widget _buildGrid() {
    final theme = Theme.of(context);
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      controller: _scrollController,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.72,
      ),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final item = _results[index];
        final url = widget.api.resolveMediaUrl(item['thumb'] ?? item['url']);
        return GestureDetector(
          onTap: () => Navigator.of(context).pop(url),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.medium),
            child: Stack(
              fit: StackFit.expand,
              children: [
                url.isEmpty
                    ? Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                      )
                    : Image.network(
                        url,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: Icon(
                    Icons.check_circle,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
