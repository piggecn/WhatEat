import 'package:flutter/material.dart';

import '../models/recipe_draft.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';
import 'recipe_edit_screen.dart';

/// 链接导入：豆果美食等菜谱网页 URL → 服务端解析成草稿（对齐网页端「🔗 链接导入」）
class UrlImportScreen extends StatefulWidget {
  final ApiClient api;

  const UrlImportScreen({super.key, required this.api});

  @override
  State<UrlImportScreen> createState() => _UrlImportScreenState();
}

class _UrlImportScreenState extends State<UrlImportScreen> {
  final _controller = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final url = _controller.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('先粘贴菜谱网页链接')));
      return;
    }
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final data = await widget.api.fetchUrlImport(url);
      if (!mounted) return;
      final title = (data['title'] ?? '').toString().trim();
      final ingredients = (data['ingredients'] as List?) ?? const [];
      final steps = (data['steps'] as List?) ?? const [];
      if (title.isEmpty && ingredients.isEmpty && steps.isEmpty) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('这个链接解析不出内容，试试复制全文用「粘贴文本导入」'),
        ));
        return;
      }
      // fetch-url 返回 publish 兼容结构（ingredients 含 name/amount/unit，steps 为对象）
      final draft = RecipeDraft.fromPrepare(data);
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => RecipeEditScreen(api: widget.api, draft: draft),
        ),
      );
      if (!mounted) return;
      setState(() => _loading = false);
      if (saved == true) {
        Navigator.of(context).pop(true);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('解析失败，请重试')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('链接导入')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              '粘贴菜谱网页链接',
              style: AppTypography.h3.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '支持豆果美食等菜谱页；公众号/小红书等文案请用「粘贴文本导入」',
              style: AppTypography.caption.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.url,
              maxLines: 2,
              minLines: 1,
              decoration: const InputDecoration(
                hintText: 'https://www.douguo.com/cookbook/xxxx.html',
                prefixIcon: Icon(Icons.link),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _loading ? null : _import,
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.download_outlined),
                label: Text(_loading ? '解析中…' : '解析并导入'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
