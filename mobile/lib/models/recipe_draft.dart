import 'recipe.dart';

class RecipeDraft {
  final String title;
  final String? description;
  final String? category;
  final List<String> mealTags;
  final int servings;
  final int? prepTime;
  final int? cookTime;
  final String? imagePath;
  final List<Ingredient> ingredients;
  final List<RecipeStep> steps;

  const RecipeDraft({
    this.title = '',
    this.description,
    this.category,
    this.mealTags = const [],
    this.servings = 2,
    this.prepTime,
    this.cookTime,
    this.imagePath,
    this.ingredients = const [],
    this.steps = const [],
  });

  factory RecipeDraft.fromPrepare(Map<String, dynamic> json) {
    final ingredientList = (json['ingredients'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((e) => Ingredient.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    final stepList = (json['steps'] as List<dynamic>? ?? const [])
        .map((e) {
          if (e is Map) {
            return RecipeStep(description: (e['description'] ?? '').toString());
          }
          return RecipeStep(description: e.toString().trim());
        })
        .where((e) => e.description.trim().isNotEmpty)
        .toList();
    return RecipeDraft(
      title: (json['title'] ?? '').toString(),
      description: _optString(json['description']),
      category: _optString(json['category']),
      mealTags: _stringList(json['meal_tags']),
      servings: _int(json['servings']) ?? 2,
      prepTime: _int(json['prep_time']),
      cookTime: _int(json['cook_time']),
      imagePath:
          _optString(json['image_path']) ?? _optString(json['thumb']),
      ingredients: ingredientList,
      steps: stepList,
    );
  }

  factory RecipeDraft.fromPaste(Map<String, dynamic> json) {
    final ingredientList = (json['ingredients'] as List<dynamic>? ?? const [])
        .map((e) {
          if (e is Map) {
            return Ingredient.fromJson(Map<String, dynamic>.from(e));
          }
          return Ingredient(name: e.toString().trim());
        })
        .where((e) => e.name.isNotEmpty)
        .toList();
    final stepList = (json['steps'] as List<dynamic>? ?? const [])
        .map((e) => RecipeStep(description: e.toString().trim()))
        .where((e) => e.description.isNotEmpty)
        .toList();
    return RecipeDraft(
      title: (json['title'] ?? '').toString(),
      ingredients: ingredientList,
      steps: stepList,
    );
  }

  static String? _optString(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static int? _int(dynamic value) {
    if (value == null) return null;
    return int.tryParse(value.toString());
  }

  static List<String> _stringList(dynamic value) {
    if (value is List) {
      return value
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return const [];
  }
}
