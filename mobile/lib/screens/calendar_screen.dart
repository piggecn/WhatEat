import 'package:flutter/material.dart';

import '../models/calendar.dart';
import '../models/recipe.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../widgets/recipe_image.dart';
import '../widgets/state_views.dart';
import 'recipe_detail_screen.dart';

class CalendarScreen extends StatefulWidget {
  final ApiClient api;

  const CalendarScreen({super.key, required this.api});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  static const _weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];
  static const _mealTypes = ['breakfast', 'lunch', 'dinner'];

  DateTime _selectedDate = DateTime.now();
  DateTime _monthDate = DateTime.now();
  bool _monthView = true;

  Map<String, MonthDayInfo> _monthDays = {};
  List<CalendarDay> _weekDays = [];
  bool _loadingMonth = true;
  bool _loadingWeek = true;
  bool _filling = false;

  @override
  void initState() {
    super.initState();
    _loadMonth();
    _loadWeek();
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _fmtMonth(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';

  Future<void> _loadMonth() async {
    setState(() => _loadingMonth = true);
    try {
      final (year, month, days) =
          await widget.api.calendarMonth(_fmtMonth(_monthDate));
      if (!mounted) return;
      setState(() {
        _monthDays = {for (final d in days) d.date: d};
        if (year > 0 && month > 0) {
          _monthDate = DateTime(year, month);
        }
        _loadingMonth = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _monthDays = {};
        _loadingMonth = false;
      });
    }
  }

  Future<void> _loadWeek() async {
    setState(() => _loadingWeek = true);
    try {
      final days = await widget.api.calendarWeek(_fmt(_selectedDate));
      if (!mounted) return;
      setState(() {
        _weekDays = days;
        _loadingWeek = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _weekDays = [];
        _loadingWeek = false;
      });
    }
  }

  void _prevMonth() {
    setState(() {
      _monthDate = DateTime(_monthDate.year, _monthDate.month - 1);
    });
    _loadMonth();
  }

  void _nextMonth() {
    setState(() {
      _monthDate = DateTime(_monthDate.year, _monthDate.month + 1);
    });
    _loadMonth();
  }

  void _goToday() {
    final now = DateTime.now();
    setState(() {
      _selectedDate = DateTime(now.year, now.month, now.day);
      _monthDate = DateTime(now.year, now.month);
      _monthView = false;
    });
    _loadMonth();
    _loadWeek();
  }

  Future<void> _selectDay(DateTime date) async {
    setState(() {
      _selectedDate = DateTime(date.year, date.month, date.day);
    });
    await _loadWeek();
    if (!mounted) return;
    _showDayDetail();
  }

  Future<void> _showDayDetail() async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DayDetailSheet(
        api: widget.api,
        date: _selectedDate,
        day: _weekDays.firstWhere(
          (d) => d.date == _fmt(_selectedDate),
          orElse: () => CalendarDay(
            date: _fmt(_selectedDate),
            weekday: '',
          ),
        ),
      ),
    );
    if (changed == true) {
      await _loadWeek();
      if (mounted) await _loadMonth();
    }
  }

  /// 对本周空槽逐个随机 + 排入（与网页端行为一致，含自动放宽条件）
  Future<void> _randomFillWeek() async {
    if (_filling || _weekDays.isEmpty) return;
    setState(() => _filling = true);
    int filled = 0;
    try {
      for (final day in _weekDays) {
        for (final mt in _mealTypes) {
          if (day.slotsOf(mt).isNotEmpty) continue;
          try {
            final r = await widget.api.randomRecipe(mealType: mt);
            if (r.empty == true || r.id == 0) continue;
            await widget.api.createPlan(
              date: day.date,
              mealType: mt,
              recipeId: r.id,
            );
            filled++;
          } catch (_) {
            // 单个失败不影响后续
          }
        }
      }
    } finally {
      if (mounted) setState(() => _filling = false);
    }
    await _loadWeek();
    if (mounted) await _loadMonth();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            filled > 0 ? '已随机填充 $filled 餐' : '本周没有需要填充的空餐'),
      ),
    );
  }

  void _openRecipe(int recipeId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecipeDetailScreen(api: widget.api, recipeId: recipeId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('日历'),
        actions: [
          IconButton(
            tooltip: '购物清单',
            icon: const Icon(Icons.shopping_cart_outlined),
            onPressed: () => _showShoppingList(),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildHeader(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: true,
                  label: Text('月视图'),
                  icon: Icon(Icons.calendar_view_month),
                ),
                ButtonSegment(
                  value: false,
                  label: Text('周视图'),
                  icon: Icon(Icons.view_week_outlined),
                ),
              ],
              selected: {_monthView},
              onSelectionChanged: (selection) {
                setState(() => _monthView = selection.first);
              },
            ),
          ),
          Expanded(
            child: _monthView ? _buildMonthView() : _buildWeekView(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: _monthView ? _prevMonth : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Center(
              child: Text(
                _monthView
                    ? '${_monthDate.year} 年 ${_monthDate.month} 月'
                    : '${_selectedDate.year} 年 ${_selectedDate.month} 月',
                style: AppTypography.h3.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: _monthView ? _nextMonth : null,
            icon: const Icon(Icons.chevron_right),
          ),
          TextButton(onPressed: _goToday, child: const Text('今天')),
        ],
      ),
    );
  }

  Widget _buildMonthView() {
    if (_loadingMonth) {
      return const LoadingState(message: '加载日历...');
    }
    final firstDay = DateTime(_monthDate.year, _monthDate.month, 1);
    final daysInMonth = DateTime(_monthDate.year, _monthDate.month + 1, 0).day;
    final leadingBlanks = firstDay.weekday - 1;
    final totalCells = leadingBlanks + daysInMonth;
    final rows = (totalCells / 7).ceil();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: _weekdayLabels
                .map((label) => Expanded(
                      child: Center(
                        child: Text(
                          label,
                          style: AppTypography.caption.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ),
                    ))
                .toList(),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 0.9,
            ),
            itemCount: rows * 7,
            itemBuilder: (context, index) {
              final dayNumber = index - leadingBlanks + 1;
              if (dayNumber < 1 || dayNumber > daysInMonth) {
                return const SizedBox.shrink();
              }
              final date = DateTime(_monthDate.year, _monthDate.month, dayNumber);
              final info = _monthDays[_fmt(date)];
              final isSelected = _fmt(date) == _fmt(_selectedDate);
              return _DayCell(
                dayNumber: dayNumber,
                info: info,
                isSelected: isSelected,
                isToday: _fmt(date) == _fmt(DateTime.now()),
                onTap: () => _selectDay(date),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildWeekView() {
    if (_loadingWeek) {
      return const LoadingState(message: '加载中...');
    }
    if (_weekDays.isEmpty) {
      return const EmptyState(title: '本周还没有安排');
    }
    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            itemCount: _weekDays.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final day = _weekDays[index];
              return _WeekDayCard(
                day: day,
                selected: day.date == _fmt(_selectedDate),
                onSelect: () {
                  setState(() {
                    final parts =
                        day.date.split('-').map(int.parse).toList();
                    _selectedDate = DateTime(parts[0], parts[1], parts[2]);
                  });
                  _showDayDetail();
                },
                onRecipeTap: (recipeId) => _openRecipe(recipeId),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _filling ? null : _randomFillWeek,
              icon: _filling
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_fix_high, size: 18),
              label: Text(_filling ? '正在随机填充…' : '随机填充本周空餐'),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showShoppingList() async {
    final date = _fmt(_selectedDate);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ShoppingListSheet(api: widget.api, date: date),
    );
  }
}

class _DayCell extends StatelessWidget {
  final int dayNumber;
  final MonthDayInfo? info;
  final bool isSelected;
  final bool isToday;
  final VoidCallback onTap;

  const _DayCell({
    required this.dayNumber,
    required this.info,
    required this.isSelected,
    required this.isToday,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected
                  ? AppColors.primary
                  : isToday
                      ? AppColors.primary.withAlpha(30)
                      : Colors.transparent,
            ),
            child: Text(
              '$dayNumber',
              style: AppTypography.body.copyWith(
                color: isSelected
                    ? Colors.white
                    : theme.colorScheme.onSurface,
                fontWeight: isSelected || isToday
                    ? FontWeight.w600
                    : FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _dot(info?.breakfastPlanned ?? false, AppColors.primary),
              _dot(info?.lunchPlanned ?? false, AppColors.primary),
              _dot(info?.dinnerPlanned ?? false, AppColors.primary),
              _dot(info?.breakfastAte ?? false, AppColors.success),
              _dot(info?.lunchAte ?? false, AppColors.success),
              _dot(info?.dinnerAte ?? false, AppColors.success),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dot(bool active, Color color) {
    return Container(
      width: 5,
      height: 5,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? color : Colors.transparent,
      ),
    );
  }
}

class _WeekDayCard extends StatelessWidget {
  final CalendarDay day;
  final bool selected;
  final VoidCallback onSelect;
  final ValueChanged<int> onRecipeTap;

  const _WeekDayCard({
    required this.day,
    required this.selected,
    required this.onSelect,
    required this.onRecipeTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parts = day.date.split('-').map(int.parse).toList();
    final date = DateTime(parts[0], parts[1], parts[2]);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(AppRadius.medium),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onSelect,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '${date.month}月${date.day}日',
                    style: AppTypography.h3.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '周${_weekdayLabel(date.weekday)}',
                    style: AppTypography.caption.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (selected) ...[
                    const Spacer(),
                    const Icon(Icons.check_circle,
                        size: 18, color: AppColors.primary),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              _slotRow('早', day.breakfast, theme),
              _slotRow('午', day.lunch, theme),
              _slotRow('晚', day.dinner, theme),
            ],
          ),
        ),
      ),
    );
  }

  String _weekdayLabel(int weekday) {
    const labels = ['一', '二', '三', '四', '五', '六', '日'];
    return labels[weekday - 1];
  }

  Widget _slotRow(String label, List<MealSlot> slots, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary.withAlpha(24),
              borderRadius: BorderRadius.circular(AppRadius.small),
            ),
            child: Text(
              label,
              style: AppTypography.tag.copyWith(color: AppColors.primary),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: slots.isEmpty
                ? Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      '未安排',
                      style: AppTypography.caption.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final slot in slots)
                        InkWell(
                          onTap: slot.recipeId == null
                              ? null
                              : () => onRecipeTap(slot.recipeId!),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: theme
                                  .colorScheme.surfaceContainerHighest
                                  .withAlpha(90),
                              borderRadius: BorderRadius.circular(
                                  AppRadius.small),
                            ),
                            child: Text(
                              slot.title ?? '已安排',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.caption.copyWith(
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _DayDetailSheet extends StatefulWidget {
  final ApiClient api;
  final DateTime date;
  final CalendarDay day;

  const _DayDetailSheet({
    required this.api,
    required this.date,
    required this.day,
  });

  @override
  State<_DayDetailSheet> createState() => _DayDetailSheetState();
}

class _DayDetailSheetState extends State<_DayDetailSheet> {
  late CalendarDay _day = widget.day;
  bool _busy = false;
  bool _dirty = false;

  String get _dateStr =>
      '${widget.date.year}-${widget.date.month.toString().padLeft(2, '0')}-${widget.date.day.toString().padLeft(2, '0')}';

  void _openRecipe(int recipeId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecipeDetailScreen(api: widget.api, recipeId: recipeId),
      ),
    );
  }

  Future<void> _addPlan(String mealType) async {
    final recipe = await showModalBottomSheet<Recipe>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RecipePickerSheet(api: widget.api),
    );
    if (recipe == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.api.createPlan(
        date: _dateStr,
        mealType: mealType,
        recipeId: recipe.id,
      );
      await _reload();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _dirty = true;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已添加安排')));
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('添加失败，请重试')));
    }
  }

  Future<void> _deleteOne(String mealType, MealSlot slot) async {
    if (slot.recipeId == null) return;
    setState(() => _busy = true);
    try {
      await widget.api.deletePlan(
        date: _dateStr,
        mealType: mealType,
        recipeId: slot.recipeId,
      );
      await _reload();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _dirty = true;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已移除这道菜')));
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('删除失败，请重试')));
    }
  }

  Future<void> _reload() async {
    final days = await widget.api.calendarWeek(_dateStr);
    if (!mounted) return;
    setState(() {
      _day = days.firstWhere(
        (d) => d.date == _dateStr,
        orElse: () => CalendarDay(date: _dateStr, weekday: ''),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope<bool>(
      // 关闭时把「是否改动过」传回给日历页，用于刷新周/月数据
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && Navigator.of(context).canPop()) {
          Navigator.of(context).pop(_dirty);
        }
      },
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${widget.date.month}月${widget.date.day}日 安排',
                style: AppTypography.h2.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 16),
              _mealSection(theme, '早餐', 'breakfast', _day.breakfast),
              _mealSection(theme, '午餐', 'lunch', _day.lunch),
              _mealSection(theme, '晚餐', 'dinner', _day.dinner),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mealSection(
      ThemeData theme, String label, String mealType, List<MealSlot> slots) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                label,
                style: AppTypography.body.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                for (final slot in slots)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withAlpha(120),
                        borderRadius:
                            BorderRadius.circular(AppRadius.small),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: slot.recipeId == null
                                  ? null
                                  : () => _openRecipe(slot.recipeId!),
                              child: Text(
                                slot.title ?? '已安排',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: _busy
                                ? null
                                : () => _deleteOne(mealType, slot),
                            tooltip: '移除这道菜',
                          ),
                        ],
                      ),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _addPlan(mealType),
                  icon: Icon(slots.isEmpty ? Icons.add : Icons.playlist_add,
                      size: 18),
                  label: Text(slots.isEmpty ? '添加' : '再加一道'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecipePickerSheet extends StatefulWidget {
  final ApiClient api;

  const _RecipePickerSheet({required this.api});

  @override
  State<_RecipePickerSheet> createState() => _RecipePickerSheetState();
}

class _RecipePickerSheetState extends State<_RecipePickerSheet> {
  final _controller = TextEditingController();
  List<Recipe> _recipes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    setState(() => _loading = true);
    try {
      final result = await widget.api.fetchRecipes(
        page: 1,
        limit: 50,
        q: q.trim().isEmpty ? null : q.trim(),
      );
      if (!mounted) return;
      setState(() {
        _recipes = result.$1;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _recipes = [];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _controller,
              onSubmitted: _search,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: '搜索菜谱',
                prefixIcon: const Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const LoadingState(message: '加载中...')
                : _recipes.isEmpty
                    ? const EmptyState(title: '没有找到菜谱')
                    : ListView.separated(
                        itemCount: _recipes.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final recipe = _recipes[index];
                          return ListTile(
                            leading: SizedBox(
                              width: 48,
                              height: 48,
                              child: ClipRRect(
                                borderRadius:
                                    BorderRadius.circular(AppRadius.small),
                                child: RecipeImage(
                                  url: widget.api.resolveMediaUrl(
                                      recipe.imageUrl ?? recipe.imagePath),
                                  iconSize: 20,
                                ),
                              ),
                            ),
                            title: Text(
                              recipe.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: recipe.category != null
                                ? Text(recipe.category!)
                                : null,
                            onTap: () => Navigator.of(context).pop(recipe),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _ShoppingListSheet extends StatefulWidget {
  final ApiClient api;
  final String date;

  const _ShoppingListSheet({required this.api, required this.date});

  @override
  State<_ShoppingListSheet> createState() => _ShoppingListSheetState();
}

class _ShoppingListSheetState extends State<_ShoppingListSheet> {
  ShoppingListData _data = const ShoppingListData();
  bool _loading = true;
  bool _byDay = false;
  final Set<String> _checked = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await widget.api.shoppingList(widget.date);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _data = const ShoppingListData();
        _loading = false;
      });
    }
  }

  void _toggleCheck(String key) {
    setState(() {
      if (!_checked.remove(key)) _checked.add(key);
    });
  }

  bool _isChecked(String name, String? unit) => _checked.contains('$name|$unit');

  String _amountText(ShoppingItem item) {
    final amount = item.displayAmount;
    return [
      if (amount.isNotEmpty) amount,
      if (item.unit != null) item.unit!,
    ].where((e) => e.isNotEmpty).join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parts = widget.date.split('-').map(int.parse).toList();
    final hasByDay = _data.byDay.isNotEmpty;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                '${parts[1]}月${parts[2]}日所在周 · 购物清单',
                style: AppTypography.h2.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('汇总清单')),
                  ButtonSegment(value: true, label: Text('按天清单')),
                ],
                selected: {_byDay},
                onSelectionChanged: (s) => setState(() => _byDay = s.first),
              ),
            ),
            Expanded(
              child: _loading
                  ? const LoadingState(message: '加载中...')
                  : (_byDay
                          ? (_data.byDay.isEmpty)
                          : _data.items.isEmpty)
                  ? const EmptyState(
                      icon: Icons.shopping_cart_outlined,
                      title: '没有购物清单',
                      subtitle: '先为这一周安排餐食吧',
                    )
                  : (_byDay && !hasByDay)
                      ? const EmptyState(
                          icon: Icons.shopping_cart_outlined,
                          title: '没有按天清单',
                          subtitle: '本周没有已安排的餐食',
                        )
                      : _byDay
                          ? _buildByDayList(theme)
                          : _buildSummaryList(theme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryList(ThemeData theme) {
    return ListView.separated(
      itemCount: _data.items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = _data.items[index];
        final key = '${item.name}|${item.unit}';
        return CheckboxListTile(
          value: _isChecked(item.name, item.unit),
          onChanged: (_) => _toggleCheck(key),
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(
            item.name,
            style: _isChecked(item.name, item.unit)
                ? TextStyle(
                    decoration: TextDecoration.lineThrough,
                    color: theme.colorScheme.onSurfaceVariant,
                  )
                : null,
          ),
          subtitle: (item.amounts.length > 1 || item.total == null) &&
                  item.amounts.isNotEmpty &&
                  item.total != null
              ? Text('来自 ${item.amounts.join(' + ')}')
              : null,
          secondary: Text(
            _amountText(item),
            style: AppTypography.caption.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        );
      },
    );
  }

  Widget _buildByDayList(ThemeData theme) {
    return ListView.builder(
      itemCount: _data.byDay.length,
      itemBuilder: (context, index) {
        final day = _data.byDay[index];
        final parts = day.date.split('-').map(int.parse).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                '${parts[1]}月${parts[2]}日 周${day.weekday}',
                style: AppTypography.h3.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            for (final meal in day.meals) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
                child: Text(
                  '${meal.label} · ${meal.recipes.join('、')}',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ),
              for (final item in meal.items)
                CheckboxListTile(
                  dense: true,
                  value: _isChecked(item.name, item.unit),
                  onChanged: (_) => _toggleCheck('${item.name}|${item.unit}'),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    item.name,
                    style: _isChecked(item.name, item.unit)
                        ? TextStyle(
                            decoration: TextDecoration.lineThrough,
                            color: theme.colorScheme.onSurfaceVariant,
                          )
                        : null,
                  ),
                  secondary: Text(
                    _amountText(item),
                    style: AppTypography.caption.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
            if (index != _data.byDay.length - 1)
              const Divider(height: 16),
          ],
        );
      },
    );
  }
}
