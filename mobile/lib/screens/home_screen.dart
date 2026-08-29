import 'package:flutter/material.dart';

import '../models/meal.dart';
import '../models/recipe.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../widgets/fr_tag.dart';
import '../widgets/recipe_card.dart';
import '../widgets/recipe_image.dart';
import '../widgets/state_views.dart';
import 'online_recipe_screen.dart';
import 'paste_import_screen.dart';
import 'recipe_detail_screen.dart';
import 'recipe_edit_screen.dart';

class HomeScreen extends StatefulWidget {
  final ApiClient api;

  const HomeScreen({super.key, required this.api});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _categories = ['全部', '早餐', '午餐', '晚餐', '甜点', '小吃', '饮品'];

  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  final _carouselController = PageController();

  List<CarouselItem> _carousel = [];
  int _carouselIndex = 0;
  List<Recipe> _recipes = [];
  List<Meal> _todayMeals = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  String _query = '';
  String? _category;

  String get _today {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadInitial();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _page = 1;
    });
    await Future.wait([_loadCarousel(), _loadRecipes(), _loadTodayMeals()]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadCarousel() async {
    try {
      final items = await widget.api.fetchCarousel();
      if (!mounted) return;
      setState(() {
        _carousel = items;
        _carouselIndex = 0;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _carousel = []);
    }
  }

  Future<void> _loadRecipes() async {
    try {
      final result = await widget.api.fetchRecipes(
        page: 1,
        limit: 50,
        category: _category,
        q: _query.trim().isEmpty ? null : _query.trim(),
      );
      if (!mounted) return;
      setState(() {
        _recipes = result.$1;
        _hasMore = result.$2;
        _page = 1;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _recipes = []);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading) return;
    setState(() => _loadingMore = true);
    try {
      final result = await widget.api.fetchRecipes(
        page: _page + 1,
        limit: 50,
        category: _category,
        q: _query.trim().isEmpty ? null : _query.trim(),
      );
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

  Future<void> _loadTodayMeals() async {
    try {
      final meals = await widget.api.listMeals(_today);
      if (!mounted) return;
      setState(() => _todayMeals = meals);
    } catch (_) {
      if (!mounted) return;
      setState(() => _todayMeals = []);
    }
  }

  void _selectCategory(String? category) {
    setState(() {
      _category = category == '全部' ? null : category;
    });
    _loadRecipes();
  }

  void _search(String value) {
    setState(() => _query = value);
    _loadRecipes();
  }

  void _openDetail(Recipe recipe) {
    _openDetailById(recipe.id);
  }

  Future<void> _openDetailById(int recipeId) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RecipeDetailScreen(api: widget.api, recipeId: recipeId),
      ),
    );
    if (changed == true && mounted) {
      _loadInitial();
    }
  }

  Future<void> _openRandom() async {
    final result = await showDialog<_RandomResult>(
      context: context,
      useSafeArea: true,
      barrierColor: Colors.black.withAlpha(140),
      builder: (_) => _RandomSheet(api: widget.api),
    );
    if (!mounted || result == null) return;
    if (result.action == _RandomAction.confirmed) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已加入今天菜单')));
      _loadInitial();
    }
  }

  Future<void> _removeMeal(Meal meal) async {
    try {
      await widget.api.deleteMeal(meal.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已移除该餐记录')));
      _loadTodayMeals();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('操作失败，请重试')));
    }
  }

  String _mealTypeLabel(String type) {
    switch (type) {
      case 'breakfast':
        return '早餐';
      case 'lunch':
        return '午餐';
      case 'dinner':
        return '晚餐';
      default:
        return type;
    }
  }

  Future<void> _openCreate() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_note),
                title: const Text('手动发布'),
                subtitle: const Text('从头填写菜谱内容'),
                onTap: () => Navigator.of(context).pop('manual'),
              ),
              ListTile(
                leading: const Icon(Icons.travel_explore),
                title: const Text('在线食谱导入'),
                subtitle: const Text('搜索在线食谱库，一键导入'),
                onTap: () => Navigator.of(context).pop('online'),
              ),
              ListTile(
                leading: const Icon(Icons.content_paste),
                title: const Text('粘贴文本导入'),
                subtitle: const Text('解析小红书、备忘录等分享的文本'),
                onTap: () => Navigator.of(context).pop('paste'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (action == null || !mounted) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => switch (action) {
          'online' => OnlineRecipeScreen(api: widget.api),
          'paste' => PasteImportScreen(api: widget.api),
          _ => RecipeEditScreen(api: widget.api),
        },
      ),
    );
    if (saved == true && mounted) {
      _loadInitial();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('今天吃点啥')),
      floatingActionButton: FloatingActionButton(
        onPressed: _openCreate,
        tooltip: '发布菜谱',
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const LoadingState(message: '加载中...')
          : RefreshIndicator(
              onRefresh: _loadInitial,
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  if (_carousel.isNotEmpty)
                    SliverToBoxAdapter(child: _buildCarousel()),
                  SliverToBoxAdapter(child: _buildRandomButton()),
                  if (_todayMeals.isNotEmpty)
                    SliverToBoxAdapter(child: _buildTodayMeals()),
                  SliverToBoxAdapter(child: _buildSearchAndFilters()),
                  if (_recipes.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyState(title: '还没有菜谱', subtitle: '试试其他分类或关键词'),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: 0.68,
                            ),
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final recipe = _recipes[index];
                          return RecipeCard(
                            recipe: recipe,
                            api: widget.api,
                            onTap: () => _openDetail(recipe),
                            onFavoriteChanged: (_) => _loadRecipes(),
                          );
                        }, childCount: _recipes.length),
                      ),
                    ),
                  if (_loadingMore)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            ),
    );
  }

  Widget _buildCarousel() {
    return Column(
      children: [
        SizedBox(
          height: 160,
          child: PageView.builder(
            controller: _carouselController,
            itemCount: _carousel.length,
            onPageChanged: (index) => setState(() => _carouselIndex = index),
            itemBuilder: (context, index) {
              final item = _carousel[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.large),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      RecipeImage(
                        url: widget.api.resolveMediaUrl(item.imageUrl),
                        fit: BoxFit.cover,
                        iconSize: 56,
                      ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black54],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 12,
                        child: Row(
                          children: [
                            if (item.category != null &&
                                item.category!.isNotEmpty) ...[
                              FrTag(
                                item.category!,
                                background: Colors.white.withAlpha(200),
                                foreground: AppColors.primary,
                              ),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.h3.copyWith(
                                  color: Colors.white,
                                  shadows: const [
                                    Shadow(blurRadius: 8, color: Colors.black54),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Icon(
                          Icons.chevron_right,
                          size: 22,
                          color: Colors.white.withAlpha(200),
                        ),
                      ),
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _openDetailById(item.id),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        if (_carousel.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _carousel.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: i == _carouselIndex ? 16 : 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: i == _carouselIndex
                          ? AppColors.primary
                          : AppColors.primary.withAlpha(70),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildRandomButton() {
    final shuffleColor = Colors.white.withAlpha(220);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Material(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(AppRadius.large),
        elevation: 6,
        shadowColor: AppColors.primary.withAlpha(120),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.large),
          onTap: _openRandom,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.casino_outlined,
                  color: Colors.white,
                  size: 26,
                ),
                const SizedBox(width: 12),
                Text(
                  '今天吃点啥？',
                  style: AppTypography.h2.copyWith(color: Colors.white),
                ),
                const SizedBox(width: 12),
                Icon(
                  Icons.shuffle,
                  color: shuffleColor,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTodayMeals() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '今日已吃',
            style: AppTypography.h3.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _todayMeals.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final meal = _todayMeals[index];
                return InputChip(
                  avatar: const Icon(Icons.check_circle, size: 16),
                  label: Text(
                    '${_mealTypeLabel(meal.mealType)} · ${meal.recipeTitle ?? '菜谱'}',
                  ),
                  onPressed: () => _openDetailById(meal.recipeId),
                  onDeleted: () => _removeMeal(meal),
                  deleteIconColor: theme.colorScheme.error,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            onSubmitted: _search,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: '搜索菜谱',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _search('');
                      },
                    ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final category = _categories[index];
                final selected =
                    (category == '全部' && _category == null) ||
                    _category == category;
                return ChoiceChip(
                  label: Text(category),
                  selected: selected,
                  onSelected: (_) => _selectCategory(category),
                  selectedColor: theme.colorScheme.primary.withAlpha(40),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

enum _RandomAction { closed, confirmed }

class _RandomResult {
  final _RandomAction action;

  const _RandomResult(this.action);
}

class _RandomSheet extends StatefulWidget {
  final ApiClient api;

  const _RandomSheet({required this.api});

  @override
  State<_RandomSheet> createState() => _RandomSheetState();
}

class _RandomSheetState extends State<_RandomSheet> {
  static const _categories = ['早餐', '午餐', '晚餐', '甜点', '小吃', '饮品'];
  static const _mealTypes = ['早餐', '午餐', '晚餐'];

  String? _category;
  String? _mealType;
  bool _excludeRecent = false;
  Recipe? _recipe;
  bool _loading = true;
  bool _confirming = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final recipe = await widget.api.randomRecipe(
        category: _category,
        mealType: _mealTypeCode,
        excludeRecentDays: _excludeRecent ? 3 : null,
      );
      if (!mounted) return;
      setState(() {
        _recipe = recipe;
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
        _error = '获取失败，请重试';
        _loading = false;
      });
    }
  }

  String? get _mealTypeCode {
    switch (_mealType) {
      case '早餐':
        return 'breakfast';
      case '午餐':
        return 'lunch';
      case '晚餐':
        return 'dinner';
      default:
        return null;
    }
  }

  Future<void> _confirm() async {
    final recipe = _recipe;
    if (recipe == null || _confirming) return;
    setState(() => _confirming = true);
    try {
      final now = DateTime.now();
      await widget.api.createMeal(
        recipeId: recipe.id,
        mealType: _mealTypeCode ?? 'dinner',
        date: '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
      );
      if (!mounted) return;
      Navigator.of(context).pop(const _RandomResult(_RandomAction.confirmed));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _confirming = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _confirming = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('记录失败，请重试')));
    }
  }

  void _resetFilter() {
    setState(() {
      _category = null;
      _mealType = null;
      _excludeRecent = false;
    });
    _fetch();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = MediaQuery.sizeOf(context).width >= 600;
    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.large),
      ),
      insetPadding: isDesktop
          ? const EdgeInsets.symmetric(horizontal: 64, vertical: 32)
          : const EdgeInsets.symmetric(horizontal: 12),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: isDesktop
            ? const BoxConstraints(maxHeight: 720)
            : BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.88),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
              child: Row(
                children: [
                  const Icon(Icons.casino_outlined, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '今天吃点啥？',
                      style: AppTypography.h2.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(
                      const _RandomResult(_RandomAction.closed),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(child: SingleChildScrollView(child: _buildBody(theme))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: _buildActions(theme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const SizedBox(
        height: 260,
        child: LoadingState(message: '正在挑选...'),
      );
    }
    if (_error != null) {
      return EmptyState(
        icon: Icons.search_off,
        title: _error!,
        subtitle: '换个条件试试，或者放宽筛选',
        action: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton.icon(
              onPressed: _resetFilter,
              icon: const Icon(Icons.rotate_left),
              label: const Text('重置筛选'),
            ),
            FilledButton.icon(
              onPressed: _fetch,
              icon: const Icon(Icons.refresh),
              label: const Text('再试一次'),
            ),
          ],
        ),
      );
    }
    final recipe = _recipe;
    if (recipe == null) return const SizedBox.shrink();
    if (recipe.empty ?? false) {
      return EmptyState(
        icon: Icons.restaurant_menu,
        title: recipe.message ?? '这个条件下没有可选的食谱了',
        action: TextButton.icon(
          onPressed: _resetFilter,
          icon: const Icon(Icons.rotate_left),
          label: const Text('重置筛选'),
        ),
      );
    }
    final imageUrl =
        widget.api.resolveMediaUrl(recipe.imageUrl ?? recipe.imagePath);
    final minutes = (recipe.prepTime ?? 0) + (recipe.cookTime ?? 0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.medium),
            child: SizedBox(
              height: 150,
              width: double.infinity,
              child: RecipeImage(
                url: imageUrl,
                fit: BoxFit.cover,
                iconSize: 52,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            recipe.title,
            style: AppTypography.h3.copyWith(color: theme.colorScheme.onSurface),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (recipe.category != null && recipe.category!.isNotEmpty) ...[
                FrTag(recipe.category!),
                const SizedBox(width: 8),
              ],
              if (minutes > 0)
                Text(
                  '$minutes 分钟',
                  style: AppTypography.caption.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          if (recipe.message != null && recipe.message!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(AppRadius.medium),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome,
                      size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '已自动放宽条件为你挑选',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          _buildFilters(theme),
        ],
      ),
    );
  }

  Widget _buildFilters(ThemeData theme) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _DropdownField(
                label: '分类',
                icon: Icons.category_outlined,
                value: _category,
                options: _categories,
                onChanged: (v) {
                  setState(() => _category = v);
                  _fetch();
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _DropdownField(
                label: '餐次',
                icon: Icons.restaurant_menu_outlined,
                value: _mealType,
                options: _mealTypes,
                onChanged: (v) {
                  setState(() => _mealType = v);
                  _fetch();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        CheckboxListTile(
          value: _excludeRecent,
          onChanged: (v) {
            setState(() => _excludeRecent = v ?? false);
            _fetch();
          },
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: Text(
            '排除最近 3 天吃过',
            style: AppTypography.caption.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActions(ThemeData theme) {
    final recipe = _recipe;
    final disabled = _loading || _confirming || recipe == null || (recipe.empty ?? false);
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: disabled ? null : _resetFilter,
            icon: const Icon(Icons.rotate_left),
            label: const Text('重置筛选'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: disabled ? null : _fetch,
            icon: const Icon(Icons.refresh),
            label: const Text('换一个'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: FilledButton.icon(
            onPressed: disabled ? null : _confirm,
            icon: _confirming
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: Text(_confirming ? '记录中…' : '就它了'),
          ),
        ),
      ],
    );
  }
}

class _DropdownField extends StatelessWidget {
  final String label;
  final IconData icon;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  const _DropdownField({
    required this.label,
    required this.icon,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = value != null && value!.isNotEmpty;
    return InputDecorator(
      decoration: InputDecoration(
        hintText: '$label：不限',
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          borderRadius: BorderRadius.circular(AppRadius.medium),
          icon: selected
              ? Icon(icon, size: 18, color: AppColors.primary)
              : null,
          style: AppTypography.body.copyWith(
            color: selected
                ? theme.colorScheme.onSurface
                : theme.colorScheme.onSurfaceVariant,
            fontSize: 13,
          ),
          items: [
            const DropdownMenuItem(value: null, child: Text('不限')),
            for (final option in options)
              DropdownMenuItem(value: option, child: Text(option)),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}
