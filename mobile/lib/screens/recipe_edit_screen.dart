import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/recipe.dart';
import '../models/recipe_draft.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../widgets/recipe_image.dart';
import 'online_image_search_screen.dart';

class RecipeEditScreen extends StatefulWidget {
  final ApiClient api;
  final Recipe? recipe;
  final RecipeDraft? draft;

  const RecipeEditScreen({
    super.key,
    required this.api,
    this.recipe,
    this.draft,
  });

  @override
  State<RecipeEditScreen> createState() => _RecipeEditScreenState();
}

class _IngredientDraft {
  String name = '';
  String amount = '';
  String unit = '';
}

class _StepDraft {
  String description = '';
}

class _RecipeEditScreenState extends State<RecipeEditScreen> {
  static const _categories = ['早餐', '午餐', '晚餐', '甜点', '小吃', '饮品'];
  static const _mealTagMap = {'早餐': 'breakfast', '午餐': 'lunch', '晚餐': 'dinner'};

  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _servingsController = TextEditingController(text: '2');
  final _prepController = TextEditingController();
  final _cookController = TextEditingController();

  String? _category;
  final Set<String> _mealTags = {};
  final Set<String> _dietTags = {};
  final _dietCustomController = TextEditingController();
  String? _imagePath;
  final List<_IngredientDraft> _ingredients = [];
  final List<_StepDraft> _steps = [];

  bool _saving = false;
  bool _uploadingImage = false;

  bool get _isEdit => widget.recipe != null;

  @override
  void initState() {
    super.initState();
    final recipe = widget.recipe;
    if (recipe != null) {
      _titleController.text = recipe.title;
      _descController.text = recipe.description ?? '';
      _servingsController.text = recipe.servings > 0
          ? '${recipe.servings}'
          : '2';
      _prepController.text = recipe.prepTime?.toString() ?? '';
      _cookController.text = recipe.cookTime?.toString() ?? '';
      _category = recipe.category;
      _mealTags.addAll(recipe.mealTags);
      _dietTags.addAll(recipe.dietTags);
      _imagePath = recipe.imagePath ?? recipe.imageUrl;
      for (final ing in recipe.ingredients) {
        _ingredients.add(
          _IngredientDraft()
            ..name = ing.name
            ..amount = ing.amount ?? ''
            ..unit = ing.unit ?? '',
        );
      }
      for (final step in recipe.steps) {
        _steps.add(_StepDraft()..description = step.description);
      }
    }
    final draft = widget.draft;
    if (recipe == null && draft != null) {
      _titleController.text = draft.title;
      _descController.text = draft.description ?? '';
      _servingsController.text =
          draft.servings > 0 ? '${draft.servings}' : '2';
      _prepController.text = draft.prepTime?.toString() ?? '';
      _cookController.text = draft.cookTime?.toString() ?? '';
      _category = draft.category;
      _mealTags.addAll(draft.mealTags);
      _imagePath = draft.imagePath;
      for (final ing in draft.ingredients) {
        _ingredients.add(
          _IngredientDraft()
            ..name = ing.name
            ..amount = ing.amount ?? ''
            ..unit = ing.unit ?? '',
        );
      }
      for (final step in draft.steps) {
        _steps.add(_StepDraft()..description = step.description);
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _servingsController.dispose();
    _prepController.dispose();
    _cookController.dispose();
    _dietCustomController.dispose();
    super.dispose();
  }

  void _addDietTag() {
    final t = _dietCustomController.text.trim();
    if (t.isEmpty || t.length > 12) return;
    setState(() {
      _dietTags.add(t);
      _dietCustomController.clear();
    });
  }

  Future<void> _pickImage() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('拍照'),
                onTap: () => Navigator.of(context).pop('camera'),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('从相册选择'),
                onTap: () => Navigator.of(context).pop('gallery'),
              ),
              ListTile(
                leading: const Icon(Icons.image_search),
                title: const Text('在线图片搜索'),
                subtitle: const Text('根据菜名搜索网络图片'),
                onTap: () => Navigator.of(context).pop('online'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (action == null || !mounted) return;
    if (action == 'online') {
      final url = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => OnlineImageSearchScreen(
            api: widget.api,
            keyword: _titleController.text.trim(),
          ),
        ),
      );
      if (url != null && url.isNotEmpty && mounted) {
        setState(() => _imagePath = url);
      }
      return;
    }
    final source =
        action == 'camera' ? ImageSource.camera : ImageSource.gallery;
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1920,
        imageQuality: 85,
      );
      if (file == null || !mounted) return;
      setState(() => _uploadingImage = true);
      final path = await widget.api.uploadImage(file.path);
      if (!mounted) return;
      setState(() {
        _imagePath = path;
        _uploadingImage = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _uploadingImage = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('图片上传失败，请重试')));
    }
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请填写菜谱标题')));
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);

    final ingredients = _ingredients
        .where((e) => e.name.trim().isNotEmpty)
        .map(
          (e) => Ingredient(
            name: e.name.trim(),
            amount: e.amount.trim().isEmpty ? null : e.amount.trim(),
            unit: e.unit.trim().isEmpty ? null : e.unit.trim(),
          ),
        )
        .toList();
    final steps = _steps
        .where((e) => e.description.trim().isNotEmpty)
        .map((e) => RecipeStep(description: e.description.trim()))
        .toList();

    final recipe = Recipe(
      id: widget.recipe?.id ?? 0,
      title: title,
      description: _descController.text.trim().isEmpty
          ? null
          : _descController.text.trim(),
      category: _category,
      mealTags: _mealTags.toList(),
      dietTags: _dietTags.toList(),
      servings: int.tryParse(_servingsController.text.trim()) ?? 2,
      prepTime: int.tryParse(_prepController.text.trim()),
      cookTime: int.tryParse(_cookController.text.trim()),
      imagePath: _imagePath,
      ingredients: ingredients,
      steps: steps,
    );

    try {
      if (_isEdit) {
        await widget.api.updateRecipe(widget.recipe!.id, recipe);
      } else {
        await widget.api.createRecipe(recipe);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('保存失败，请重试')));
    }
  }

  void _addIngredient() => setState(() => _ingredients.add(_IngredientDraft()));

  void _removeIngredient(int index) =>
      setState(() => _ingredients.removeAt(index));

  void _addStep() => setState(() => _steps.add(_StepDraft()));

  void _removeStep(int index) => setState(() => _steps.removeAt(index));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '编辑菜谱' : '发布菜谱'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _buildCoverPicker(theme),
          const SizedBox(height: 16),
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: '菜谱标题 *',
              hintText: '例如：番茄炒蛋',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _descController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '简介',
              hintText: '这道菜的特点、口感、故事…',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 20),
          _buildLabel(theme, '分类'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _categories.map((category) {
              return ChoiceChip(
                label: Text(category),
                selected: _category == category,
                onSelected: (_) => setState(() => _category = category),
                selectedColor: theme.colorScheme.primary.withAlpha(40),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          _buildLabel(theme, '适用餐次'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _mealTagMap.entries.map((entry) {
              return FilterChip(
                label: Text(entry.key),
                selected: _mealTags.contains(entry.value),
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _mealTags.add(entry.value);
                    } else {
                      _mealTags.remove(entry.value);
                    }
                  });
                },
                selectedColor: theme.colorScheme.primary.withAlpha(40),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          _buildLabel(theme, '忌口标签'),
          const SizedBox(height: 4),
          Text(
            '可不选；推荐时自动排除',
            style: AppTypography.caption.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in dietTagPresets)
                FilterChip(
                  label: Text(tag),
                  selected: _dietTags.contains(tag),
                  onSelected: (selected) {
                    setState(() {
                      selected ? _dietTags.add(tag) : _dietTags.remove(tag);
                    });
                  },
                  selectedColor: theme.colorScheme.primary.withAlpha(40),
                ),
              for (final tag
                  in _dietTags.where((t) => !dietTagPresets.contains(t)))
                InputChip(
                  label: Text(tag),
                  onDeleted: () => setState(() => _dietTags.remove(tag)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _dietCustomController,
                  maxLength: 12,
                  decoration: const InputDecoration(
                    hintText: '自定义忌口，如：香菜（回车添加）',
                    counterText: '',
                  ),
                  onSubmitted: (_) => _addDietTag(),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(onPressed: _addDietTag, child: const Text('添加')),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _servingsController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '份量（人）'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _prepController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '准备（分钟）'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _cookController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '烹饪（分钟）'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildSectionHeader(theme, '食材清单', Icons.shopping_basket_outlined),
          const SizedBox(height: 8),
          ..._ingredients.asMap().entries.map((entry) {
            final index = entry.key;
            return _buildIngredientRow(index);
          }),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addIngredient,
              icon: const Icon(Icons.add),
              label: const Text('添加食材'),
            ),
          ),
          const SizedBox(height: 16),
          _buildSectionHeader(theme, '烹饪步骤', Icons.format_list_numbered),
          const SizedBox(height: 8),
          ..._steps.asMap().entries.map((entry) {
            final index = entry.key;
            return _buildStepRow(index);
          }),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addStep,
              icon: const Icon(Icons.add),
              label: const Text('添加步骤'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoverPicker(ThemeData theme) {
    final imageUrl = widget.api.resolveMediaUrl(_imagePath);
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.large),
      onTap: _uploadingImage ? null : _pickImage,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.large),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (imageUrl.isNotEmpty)
                RecipeImage(url: imageUrl, fit: BoxFit.cover, iconSize: 48)
              else
                ColoredBox(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_photo_alternate_outlined,
                        size: 40,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '添加封面图',
                        style: AppTypography.body.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              if (_uploadingImage)
                ColoredBox(
                  color: Colors.black.withAlpha(90),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Colors.white),
                        SizedBox(height: 8),
                        Text('上传中…', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIngredientRow(int index) {
    final ingredient = _ingredients[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: TextFormField(
              initialValue: ingredient.name,
              decoration: const InputDecoration(hintText: '食材名'),
              onChanged: (value) => ingredient.name = value,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextFormField(
              initialValue: ingredient.amount,
              decoration: const InputDecoration(hintText: '用量'),
              onChanged: (value) => ingredient.amount = value,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 1,
            child: TextFormField(
              initialValue: ingredient.unit,
              decoration: const InputDecoration(hintText: '单位'),
              onChanged: (value) => ingredient.unit = value,
            ),
          ),
          IconButton(
            tooltip: '删除',
            onPressed: () => _removeIngredient(index),
            icon: const Icon(Icons.close, color: AppColors.error),
          ),
        ],
      ),
    );
  }

  Widget _buildStepRow(int index) {
    final step = _steps[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
            alignment: Alignment.center,
            child: Text(
              '${index + 1}',
              style: AppTypography.tag.copyWith(color: AppColors.onPrimary),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              initialValue: step.description,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: '描述这一步的做法…',
                alignLabelWithHint: true,
              ),
              onChanged: (value) => step.description = value,
            ),
          ),
          IconButton(
            tooltip: '删除',
            onPressed: () => _removeStep(index),
            icon: const Icon(Icons.close, color: AppColors.error),
          ),
        ],
      ),
    );
  }

  Widget _buildLabel(ThemeData theme, String text) {
    return Text(
      text,
      style: AppTypography.h3.copyWith(color: theme.colorScheme.onSurface),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title, IconData icon) {
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
