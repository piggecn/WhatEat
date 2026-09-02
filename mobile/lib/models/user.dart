class User {
  final int id;
  final String username;
  final String? displayName;
  final bool isAdmin;
  final String? avatar;
  final String? avatarPath;
  final String? avatarUrl;

  const User({
    required this.id,
    required this.username,
    this.displayName,
    this.isAdmin = false,
    this.avatar,
    this.avatarPath,
    this.avatarUrl,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int? ?? 0,
      username: json['username'] as String? ?? '',
      displayName: json['display_name'] as String?,
      isAdmin: json['is_admin'] as bool? ?? false,
      avatar: json['avatar'] as String?,
      avatarPath: json['avatar_path'] as String?,
      avatarUrl: json['avatar_url'] as String?,
    );
  }

  String get nickname => (displayName?.isNotEmpty ?? false) ? displayName! : username;
}

class Profile {
  final int id;
  final String username;
  final String? displayName;
  final String? avatar;
  final bool isAdmin;
  final String carouselType;
  final int carouselLimit;
  final List<String> avoidTags;

  const Profile({
    required this.id,
    required this.username,
    this.displayName,
    this.avatar,
    this.isAdmin = false,
    this.carouselType = 'most_cooked',
    this.carouselLimit = 10,
    this.avoidTags = const [],
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as int? ?? 0,
      username: json['username'] as String? ?? '',
      displayName: json['display_name'] as String?,
      avatar: json['avatar'] as String?,
      isAdmin: json['is_admin'] as bool? ?? false,
      carouselType: json['carousel_type'] as String? ?? 'most_cooked',
      carouselLimit: json['carousel_limit'] as int? ?? 10,
      avoidTags: (json['avoid_tags'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }

  String get nickname =>
      (displayName?.isNotEmpty ?? false) ? displayName! : username;
}
