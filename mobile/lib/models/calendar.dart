class MealSlot {
  final int? recipeId;
  final String? title;
  final String? imageUrl;

  const MealSlot({this.recipeId, this.title, this.imageUrl});

  bool get isEmpty => recipeId == null;

  factory MealSlot.fromJson(Map<String, dynamic> json) {
    return MealSlot(
      recipeId: json['recipe_id'] is num
          ? (json['recipe_id'] as num).toInt()
          : int.tryParse('${json['recipe_id']}'),
      title: json['title'] as String?,
      imageUrl: json['image_url'] as String?,
    );
  }
}

/// 服务端 week/month 每餐返回数组（每餐可多道菜）；兼容旧版单对象格式。
List<MealSlot> parseMealSlots(dynamic value) {
  if (value is List) {
    return value
        .whereType<Map>()
        .map((e) => MealSlot.fromJson(e.cast<String, dynamic>()))
        .toList();
  }
  if (value is Map) {
    final slot = MealSlot.fromJson(value.cast<String, dynamic>());
    return slot.isEmpty ? const [] : [slot];
  }
  return const [];
}

class CalendarDay {
  final String date;
  final String weekday;
  final List<MealSlot> breakfast;
  final List<MealSlot> lunch;
  final List<MealSlot> dinner;

  const CalendarDay({
    required this.date,
    required this.weekday,
    this.breakfast = const [],
    this.lunch = const [],
    this.dinner = const [],
  });

  List<MealSlot> slotsOf(String mealType) {
    switch (mealType) {
      case 'breakfast':
        return breakfast;
      case 'lunch':
        return lunch;
      case 'dinner':
        return dinner;
    }
    return const [];
  }

  factory CalendarDay.fromJson(Map<String, dynamic> json) {
    return CalendarDay(
      date: json['date'] as String? ?? '',
      weekday: json['weekday'] as String? ?? '',
      breakfast: parseMealSlots(json['breakfast']),
      lunch: parseMealSlots(json['lunch']),
      dinner: parseMealSlots(json['dinner']),
    );
  }
}

class MonthDayInfo {
  final String date;
  final bool hasRecords;
  final bool hasPlans;
  final bool breakfastPlanned;
  final bool lunchPlanned;
  final bool dinnerPlanned;
  final bool breakfastAte;
  final bool lunchAte;
  final bool dinnerAte;
  final List<MealSlot> breakfast;
  final List<MealSlot> lunch;
  final List<MealSlot> dinner;

  const MonthDayInfo({
    required this.date,
    this.hasRecords = false,
    this.hasPlans = false,
    this.breakfastPlanned = false,
    this.lunchPlanned = false,
    this.dinnerPlanned = false,
    this.breakfastAte = false,
    this.lunchAte = false,
    this.dinnerAte = false,
    this.breakfast = const [],
    this.lunch = const [],
    this.dinner = const [],
  });

  List<MealSlot> slotsOf(String mealType) {
    switch (mealType) {
      case 'breakfast':
        return breakfast;
      case 'lunch':
        return lunch;
      case 'dinner':
        return dinner;
    }
    return const [];
  }

  factory MonthDayInfo.fromJson(Map<String, dynamic> json) {
    return MonthDayInfo(
      date: json['date'] as String? ?? '',
      hasRecords: json['has_records'] as bool? ?? false,
      hasPlans: json['has_plans'] as bool? ?? false,
      breakfastPlanned: json['breakfast_planned'] as bool? ?? false,
      lunchPlanned: json['lunch_planned'] as bool? ?? false,
      dinnerPlanned: json['dinner_planned'] as bool? ?? false,
      breakfastAte: json['breakfast_ate'] as bool? ?? false,
      lunchAte: json['lunch_ate'] as bool? ?? false,
      dinnerAte: json['dinner_ate'] as bool? ?? false,
      breakfast: parseMealSlots(json['breakfast']),
      lunch: parseMealSlots(json['lunch']),
      dinner: parseMealSlots(json['dinner']),
    );
  }
}

class ShoppingItem {
  final String name;
  final List<String> amounts;
  final String? unit;
  final String? total;

  const ShoppingItem({
    required this.name,
    this.amounts = const [],
    this.unit,
    this.total,
  });

  factory ShoppingItem.fromJson(Map<String, dynamic> json) {
    return ShoppingItem(
      name: json['name'] as String? ?? '',
      amounts: (json['amounts'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      unit: json['unit'] as String?,
      total: json['total']?.toString(),
    );
  }

  /// 展示用量：优先合计 total，否则逐条 amounts。
  String get displayAmount {
    if (total != null && total!.isNotEmpty) {
      return total!;
    }
    return amounts.join('、');
  }
}

class ShoppingDayMeal {
  final String mealType;
  final String label;
  final List<String> recipes;
  final List<ShoppingItem> items;

  const ShoppingDayMeal({
    required this.mealType,
    required this.label,
    this.recipes = const [],
    this.items = const [],
  });

  factory ShoppingDayMeal.fromJson(Map<String, dynamic> json) {
    return ShoppingDayMeal(
      mealType: json['meal_type'] as String? ?? '',
      label: json['label'] as String? ?? '',
      recipes: (json['recipes'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      items: (json['items'] as List<dynamic>? ?? const [])
          .map((e) => ShoppingItem.fromJson(e.cast<String, dynamic>()))
          .toList(),
    );
  }
}

class ShoppingDay {
  final String date;
  final String weekday;
  final List<ShoppingDayMeal> meals;

  const ShoppingDay({
    required this.date,
    this.weekday = '',
    this.meals = const [],
  });

  factory ShoppingDay.fromJson(Map<String, dynamic> json) {
    return ShoppingDay(
      date: json['date'] as String? ?? '',
      weekday: json['weekday'] as String? ?? '',
      meals: (json['meals'] as List<dynamic>? ?? const [])
          .map((e) => ShoppingDayMeal.fromJson(e.cast<String, dynamic>()))
          .toList(),
    );
  }
}

class ShoppingListData {
  final List<ShoppingItem> items;
  final List<ShoppingDay> byDay;

  const ShoppingListData({this.items = const [], this.byDay = const []});
}
