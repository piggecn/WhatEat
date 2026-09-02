import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/recipe_draft.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';
import 'recipe_edit_screen.dart';

class PasteImportScreen extends StatefulWidget {
  final ApiClient api;
  final String initialText;

  const PasteImportScreen({
    super.key,
    required this.api,
    this.initialText = '',
  });

  @override
  State<PasteImportScreen> createState() => _PasteImportScreenState();
}

class _PasteImportScreenState extends State<PasteImportScreen> {
  final _controller = TextEditingController();
  bool _parsing = false;
  bool _ocr = false;
  RecipeDraft? _draft;

  @override
  void initState() {
    super.initState();
    _controller.text = widget.initialText;
    if (widget.initialText.trim().isNotEmpty) {
      _parse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickAndOcr() async {
    if (_ocr) return;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 1920,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    setState(() => _ocr = true);
    try {
      final text = await widget.api.ocrImage(picked.path);
      if (!mounted) return;
      if (text.trim().isEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('没识别出文字，换张清晰点的试试')));
        return;
      }
      setState(() {
        _controller.text =
            _controller.text.trim().isEmpty ? text : '${_controller.text.trim()}\n$text';
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('识别完成，已填入文本')));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('识别失败，请重试')));
    } finally {
      if (mounted) setState(() => _ocr = false);
    }
  }

  Future<void> _parse() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先粘贴菜谱文本')));
      return;
    }
    if (_parsing) return;
    setState(() {
      _parsing = true;
      _draft = null;
    });
    try {
      final data = await widget.api.parsePaste(text);
      if (!mounted) return;
      setState(() {
        _draft = RecipeDraft.fromPaste(data);
        _parsing = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _parsing = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _parsing = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('解析失败，请重试')));
    }
  }

  Future<void> _import() async {
    final draft = _draft;
    if (draft == null) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RecipeEditScreen(api: widget.api, draft: draft),
      ),
    );
    if (saved == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('粘贴文本导入')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text(
              '粘贴小红书、备忘录等 App 分享的菜谱文本，自动识别标题、食材和步骤。',
              style: AppTypography.caption.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              maxLines: 8,
              decoration: const InputDecoration(
                hintText: '例如：\n番茄炒蛋\n食材：番茄2个、鸡蛋3个、盐适量\n步骤：\n1. 番茄切块…\n2. 鸡蛋打散…',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _ocr ? null : _pickAndOcr,
                    icon: _ocr
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.photo_camera_outlined),
                    label: Text(_ocr ? '识别中…' : '拍照识别'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _parsing ? null : _parse,
                    icon: _parsing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_fix_high),
                    label: Text(_parsing ? '解析中…' : '解析文本'),
                  ),
                ),
              ],
            ),
            if (_draft != null) ...[
              const SizedBox(height: 20),
              _buildPreview(theme, _draft!),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _import,
                icon: const Icon(Icons.edit_note),
                label: const Text('导入并编辑'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(ThemeData theme, RecipeDraft draft) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '解析结果',
              style: AppTypography.h3.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            if (draft.title.isNotEmpty) ...[
              Text(
                draft.title,
                style: AppTypography.h2.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (draft.ingredients.isNotEmpty) ...[
              Text(
                '食材（${draft.ingredients.length}）',
                style: AppTypography.body.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              ...draft.ingredients.take(6).map(
                    (ing) => Text(
                      '· ${[
                        ing.name,
                        ing.amount ?? '',
                        ing.unit ?? '',
                      ].where((e) => e.isNotEmpty).join(' ')}',
                      style: AppTypography.caption.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              if (draft.ingredients.length > 6)
                Text(
                  '… 共 ${draft.ingredients.length} 项',
                  style: AppTypography.caption.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              const SizedBox(height: 8),
            ],
            if (draft.steps.isNotEmpty) ...[
              Text(
                '步骤（${draft.steps.length}）',
                style: AppTypography.body.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              ...draft.steps.take(3).map(
                    (step) => Text(
                      '· ${step.description}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              if (draft.steps.length > 3)
                Text(
                  '… 共 ${draft.steps.length} 步',
                  style: AppTypography.caption.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
            if (draft.title.isEmpty &&
                draft.ingredients.isEmpty &&
                draft.steps.isEmpty)
              Text(
                '未能识别出有效内容，请调整文本后重试',
                style: AppTypography.caption.copyWith(color: AppColors.error),
              ),
          ],
        ),
      ),
    );
  }
}
