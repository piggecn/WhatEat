class Ingredient {
  final int? id;
  final String name;
  final String? amount;
  final String? unit;

  const Ingredient({
    this.id,
    required this.name,
    this.amount,
    this.unit,
  });

  factory Ingredient.fromJson(Map<String, dynamic> json) {
    return Ingredient(
      id: json['id'] as int?,
      name: json['name'] as String? ?? '',
      amount: json['amount'] as String?,
      unit: json['unit'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (amount != null) 'amount': amount,
      if (unit != null) 'unit': unit,
    };
  }
}

class RecipeStep {
  final int? id;
  final int? stepNumber;
  final String description;

  const RecipeStep({
    this.id,
    this.stepNumber,
    required this.description,
  });

  factory RecipeStep.fromJson(Map<String, dynamic> json) {
    return RecipeStep(
      id: json['id'] as int?,
      stepNumber: json['step_number'] as int?,
      description: json['description'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (stepNumber != null) 'step_number': stepNumber,
      'description': description,
    };
  }
}

class Recipe {
  final int id;
  final String title;
  final String? description;
  final String? category;
  final List<String> mealTags;
  final String? imagePath;
  final String? imageUrl;
  final int? prepTime;
  final int? cookTime;
  final String? author;
  final String? authorDisplayName;
  final String? authorAvatar;
  final bool isFavorite;
  final String? createdAt;
  final int servings;
  final List<Ingredient> ingredients;
  final List<RecipeStep> steps;
  final int? createdBy;
  final String? updatedAt;
  final int? totalEligible;
  final bool? empty;
  final String? message;

  const Recipe({
    required this.id,
    required this.title,
    this.description,
    this.category,
    this.mealTags = const [],
    this.imagePath,
    this.imageUrl,
    this.prepTime,
    this.cookTime,
    this.author,
    this.authorDisplayName,
    this.authorAvatar,
    this.isFavorite = false,
    this.createdAt,
    this.servings = 0,
    this.ingredients = const [],
    this.steps = const [],
    this.createdBy,
    this.updatedAt,
    this.totalEligible,
    this.empty,
    this.message,
  });

  factory Recipe.fromJson(Map<String, dynamic> json) {
    return Recipe(
      id: json['id'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
      category: json['category'] as String?,
      mealTags: (json['meal_tags'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      imagePath: json['image_path'] as String?,
      imageUrl: json['image_url'] as String?,
      prepTime: json['prep_time'] as int?,
      cookTime: json['cook_time'] as int?,
      author: json['author'] as String?,
      authorDisplayName: json['author_display_name'] as String?,
      authorAvatar: json['author_avatar'] as String?,
      isFavorite: json['is_favorite'] as bool? ?? false,
      createdAt: json['created_at'] as String?,
      servings: json['servings'] as int? ?? 0,
      ingredients: (json['ingredients'] as List<dynamic>? ?? const [])
          .map((e) => Ingredient.fromJson(e as Map<String, dynamic>))
          .toList(),
      steps: (json['steps'] as List<dynamic>? ?? const [])
          .map((e) => RecipeStep.fromJson(e as Map<String, dynamic>))
          .toList(),
      createdBy: json['created_by'] as int?,
      updatedAt: json['updated_at'] as String?,
      totalEligible: json['total_eligible'] as int?,
      empty: json['empty'] as bool?,
      message: json['message'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      if (description != null) 'description': description,
      if (category != null) 'category': category,
      'meal_tags': mealTags,
      'servings': servings,
      if (prepTime != null) 'prep_time': prepTime,
      if (cookTime != null) 'cook_time': cookTime,
      if (imagePath != null) 'image_path': imagePath,
      'ingredients': ingredients.map((e) => e.toJson()).toList(),
      'steps': steps.map((e) => e.toJson()).toList(),
    };
  }
}

class CarouselItem {
  final int id;
  final String title;
  final String? imageUrl;
  final String? category;

  const CarouselItem({
    required this.id,
    required this.title,
    this.imageUrl,
    this.category,
  });

  factory CarouselItem.fromJson(Map<String, dynamic> json) {
    return CarouselItem(
      id: json['id'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      imageUrl: json['image_url'] as String?,
      category: json['category'] as String?,
    );
  }
}
