class MealSlot {
  final int? recipeId;
  final String? title;
  final String? imageUrl;

  const MealSlot({this.recipeId, this.title, this.imageUrl});

  bool get isEmpty => recipeId == null;

  factory MealSlot.fromJson(Map<String, dynamic> json) {
    return MealSlot(
      recipeId: json['recipe_id'] as int?,
      title: json['title'] as String?,
      imageUrl: json['image_url'] as String?,
    );
  }
}

class CalendarDay {
  final String date;
  final String weekday;
  final MealSlot breakfast;
  final MealSlot lunch;
  final MealSlot dinner;

  const CalendarDay({
    required this.date,
    required this.weekday,
    this.breakfast = const MealSlot(),
    this.lunch = const MealSlot(),
    this.dinner = const MealSlot(),
  });

  factory CalendarDay.fromJson(Map<String, dynamic> json) {
    return CalendarDay(
      date: json['date'] as String? ?? '',
      weekday: json['weekday'] as String? ?? '',
      breakfast: json['breakfast'] is Map<String, dynamic>
          ? MealSlot.fromJson(json['breakfast'] as Map<String, dynamic>)
          : const MealSlot(),
      lunch: json['lunch'] is Map<String, dynamic>
          ? MealSlot.fromJson(json['lunch'] as Map<String, dynamic>)
          : const MealSlot(),
      dinner: json['dinner'] is Map<String, dynamic>
          ? MealSlot.fromJson(json['dinner'] as Map<String, dynamic>)
          : const MealSlot(),
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
  });

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
    );
  }
}

class ShoppingItem {
  final String name;
  final List<String> amounts;
  final String? unit;

  const ShoppingItem({
    required this.name,
    this.amounts = const [],
    this.unit,
  });

  factory ShoppingItem.fromJson(Map<String, dynamic> json) {
    return ShoppingItem(
      name: json['name'] as String? ?? '',
      amounts: (json['amounts'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      unit: json['unit'] as String?,
    );
  }
}
