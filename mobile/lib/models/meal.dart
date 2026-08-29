class Meal {
  final int id;
  final int userId;
  final int recipeId;
  final String mealType;
  final String date;
  final String? createdAt;
  final String? recipeTitle;
  final String? recipeImage;

  const Meal({
    required this.id,
    required this.userId,
    required this.recipeId,
    required this.mealType,
    required this.date,
    this.createdAt,
    this.recipeTitle,
    this.recipeImage,
  });

  factory Meal.fromJson(Map<String, dynamic> json) {
    return Meal(
      id: json['id'] as int? ?? 0,
      userId: json['user_id'] as int? ?? 0,
      recipeId: json['recipe_id'] as int? ?? 0,
      mealType: json['meal_type'] as String? ?? '',
      date: json['date'] as String? ?? '',
      createdAt: json['created_at'] as String?,
      recipeTitle: json['recipe_title'] as String?,
      recipeImage: json['recipe_image'] as String?,
    );
  }
}
