import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/calendar.dart';
import '../models/inventory.dart';
import '../models/meal.dart';
import '../models/recipe.dart';
import '../models/user.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  const ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class ApiClient {
  static const _timeout = Duration(seconds: 15);
  static const _uploadTimeout = Duration(seconds: 60);

  String _baseUrl = '';
  String? _token;

  String get baseUrl => _baseUrl;

  String? get token => _token;

  bool get hasBaseUrl => _baseUrl.isNotEmpty;

  static String normalizeBaseUrl(String input) {
    var url = input.trim();
    if (url.isEmpty) return '';
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  void setBaseUrl(String baseUrl) {
    _baseUrl = normalizeBaseUrl(baseUrl);
  }

  void setToken(String? token) {
    _token = token;
  }

  String resolveMediaUrl(String? value) {
    if (value == null || value.isEmpty) return '';
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    if (_baseUrl.isEmpty) return value;
    return '$_baseUrl${value.startsWith('/') ? '' : '/'}$value';
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    if (_baseUrl.isEmpty) {
      throw const ApiException('请先配置服务器地址');
    }
    final uri = Uri.parse('$_baseUrl$path');
    return query == null ? uri : uri.replace(queryParameters: query);
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Future<dynamic> _get(
    String path, {
    Map<String, String>? query,
  }) async {
    final response =
        await http.get(_uri(path, query), headers: _headers).timeout(_timeout);
    return _decode(response);
  }

  Future<dynamic> _post(String path, {Object? body}) async {
    final response = await http
        .post(
          _uri(path),
          headers: _headers,
          body: body == null ? null : jsonEncode(body),
        )
        .timeout(_timeout);
    return _decode(response);
  }

  Future<dynamic> _put(String path, {Object? body}) async {
    final response = await http
        .put(
          _uri(path),
          headers: _headers,
          body: body == null ? null : jsonEncode(body),
        )
        .timeout(_timeout);
    return _decode(response);
  }

  Future<dynamic> _delete(
    String path, {
    Object? body,
    Map<String, String>? query,
  }) async {
    final response = await http
        .delete(
          _uri(path, query),
          headers: _headers,
          body: body == null ? null : jsonEncode(body),
        )
        .timeout(_timeout);
    return _decode(response);
  }

  Future<dynamic> _sendMultipart(
    String method,
    String path, {
    Map<String, String> fields = const {},
    Map<String, String> files = const {},
  }) async {
    final request = http.MultipartRequest(method, _uri(path));
    if (_token != null) {
      request.headers['Authorization'] = 'Bearer $_token';
    }
    fields.forEach((key, value) => request.fields[key] = value);
    for (final entry in files.entries) {
      request.files.add(await http.MultipartFile.fromPath(entry.key, entry.value));
    }
    final streamed = await request.send().timeout(_uploadTimeout);
    final response = await http.Response.fromStream(streamed);
    return _decode(response);
  }

  /// POST 并返回原始字节（用于 TTS mp3 等二进制响应）
  Future<List<int>> _postBytes(String path, {Object? body}) async {
    final response = await http
        .post(
          _uri(path),
          headers: _headers,
          body: body == null ? null : jsonEncode(body),
        )
        .timeout(_uploadTimeout);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.bodyBytes;
    }
    if (response.statusCode == 401) {
      throw ApiException('登录已过期，请重新登录', statusCode: 401);
    }
    throw ApiException(_parseError(response), statusCode: response.statusCode);
  }

  dynamic _decode(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.bodyBytes.isEmpty) return const <String, dynamic>{};
      return jsonDecode(utf8.decode(response.bodyBytes));
    }
    if (response.statusCode == 401) {
      throw ApiException('登录已过期，请重新登录', statusCode: 401);
    }
    throw ApiException(
      _parseError(response),
      statusCode: response.statusCode,
    );
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return data.cast<String, dynamic>();
    return const {};
  }

  List<dynamic> _asList(dynamic data) {
    if (data is List) return data;
    return const [];
  }

  int _int(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? fallback;
    return fallback;
  }

  Map<String, dynamic> _asMapLoose(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return data.cast<String, dynamic>();
    return const {};
  }

  List<String> _asStringList(dynamic data) {
    if (data is String && data.isNotEmpty) return [data];
    if (data is List) {
      return data
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return const [];
  }

  List<Map<String, dynamic>> _asMapList(dynamic data) {
    return _asList(data)
        .map((e) => _asMapLoose(e))
        .toList();
  }

  Future<({String token, User user})> login(
    String username,
    String password,
  ) async {
    final data = await _post('/api/auth/login', body: {
      'username': username,
      'password': password,
      'remember_me': true,
    });
    final body = _asMap(data);
    final token = body['token'] as String;
    final user = User.fromJson(_asMap(body['user']));
    _token = token;
    return (token: token, user: user);
  }

  Future<User> me() async {
    final data = await _get('/api/auth/me');
    return User.fromJson(_asMap(data));
  }

  Future<(List<Recipe>, bool)> fetchRecipes({
    int page = 1,
    int limit = 50,
    String? category,
    String? q,
    String? mealType,
  }) async {
    final data = await _get(
      '/api/recipes',
      query: {
        'page': '$page',
        'limit': '$limit',
        if (category != null && category.isNotEmpty) 'category': category,
        if (q != null && q.isNotEmpty) 'q': q,
        if (mealType != null && mealType.isNotEmpty) 'meal_type': mealType,
      },
    );
    final body = _asMap(data);
    final items = _asList(body['items'])
        .map((e) => Recipe.fromJson(_asMap(e)))
        .toList();
    final total = body['total'] as int? ?? items.length;
    final hasMore = body['has_more'] as bool? ?? (page * limit < total);
    return (items, hasMore);
  }

  Future<Recipe> fetchRecipeDetail(int id) async {
    final data = await _get('/api/recipes/$id');
    return Recipe.fromJson(_asMap(data));
  }

  Future<Recipe> createRecipe(Recipe recipe) async {
    final data = await _post('/api/recipes', body: recipe.toJson());
    return Recipe.fromJson(_asMap(data));
  }

  Future<Recipe> updateRecipe(int id, Recipe recipe) async {
    final data = await _put('/api/recipes/$id', body: recipe.toJson());
    return Recipe.fromJson(_asMap(data));
  }

  Future<void> deleteRecipe(int id) async {
    await _delete('/api/recipes/$id');
  }

  Future<bool> toggleFavorite(int id) async {
    final data = await _post('/api/recipes/$id/favorite');
    return _asMap(data)['is_favorite'] as bool? ?? false;
  }

  Future<(List<Recipe>, bool, int)> fetchFavorites({
    int page = 1,
    int pageSize = 20,
  }) async {
    final data = await _get(
      '/api/recipes/favorites',
      query: {'page': '$page', 'page_size': '$pageSize'},
    );
    final body = _asMap(data);
    final items = _asList(body['items'])
        .map((e) => Recipe.fromJson(_asMap(e)))
        .toList();
    final total = _int(body['total'], fallback: items.length);
    final hasMore = body['has_more'] as bool? ?? (page * pageSize < total);
    return (items, hasMore, total);
  }

  Future<List<CarouselItem>> fetchCarousel({
    String? type,
    int? limit,
  }) async {
    final data = await _get(
      '/api/recipes/carousel',
      query: {
        if (type != null && type.isNotEmpty) 'type': type,
        if (limit != null) 'limit': '$limit',
      },
    );
    return _asList(data)
        .map((e) => CarouselItem.fromJson(_asMap(e)))
        .toList();
  }

  Future<Recipe> randomRecipe({
    String? category,
    String? mealType,
    int? excludeRecentDays,
    bool? onlyInStock,
  }) async {
    final data = await _get(
      '/api/recipes/random',
      query: {
        if (category != null && category.isNotEmpty) 'category': category,
        if (mealType != null && mealType.isNotEmpty) 'meal_type': mealType,
        if (excludeRecentDays != null) 'exclude_recent_days': '$excludeRecentDays',
        if (onlyInStock == true) 'only_in_stock': 'true',
      },
    );
    return Recipe.fromJson(_asMap(data));
  }

  // ---------- 库存（家里剩啥） ----------

  Future<List<InventoryItem>> fetchInventory() async {
    final data = await _get('/api/inventory');
    return _asList(data)
        .map((e) => InventoryItem.fromJson(_asMapLoose(e)))
        .toList();
  }

  Future<void> addInventory({
    required String name,
    String? amount,
    String? unit,
  }) async {
    await _post('/api/inventory', body: {
      'name': name,
      if (amount != null && amount.isNotEmpty) 'amount': amount,
      if (unit != null && unit.isNotEmpty) 'unit': unit,
    });
  }

  Future<void> deleteInventory(int itemId) async {
    await _delete('/api/inventory/$itemId');
  }

  Future<Meal> createMeal({
    required int recipeId,
    required String mealType,
    required String date,
  }) async {
    final data = await _post('/api/meals', body: {
      'recipe_id': recipeId,
      'meal_type': mealType,
      'date': date,
    });
    return Meal.fromJson(_asMap(data));
  }

  Future<List<Meal>> listMeals(String date) async {
    final data = await _get('/api/meals', query: {'date': date});
    return _asList(data).map((e) => Meal.fromJson(_asMap(e))).toList();
  }

  Future<List<int>> fetchRecentMealRecipeIds({int days = 7}) async {
    final data = await _get('/api/meals/recent', query: {'days': '$days'});
    return _asList(data).map((e) => (e as num).toInt()).toList();
  }

  Future<void> deleteMeal(int id) async {
    await _delete('/api/meals/$id');
  }

  Future<List<CalendarDay>> calendarWeek(String date) async {
    final data = await _get('/api/calendar/week', query: {'date': date});
    return _asList(_asMap(data)['days'])
        .map((e) => CalendarDay.fromJson(_asMap(e)))
        .toList();
  }

  Future<(int, int, List<MonthDayInfo>)> calendarMonth(String month) async {
    final data = await _get('/api/calendar/month', query: {'month': month});
    final body = _asMap(data);
    final year = int.tryParse('${body['year']}') ?? 0;
    final monthNum = int.tryParse('${body['month']}') ?? 0;
    final days = _asList(body['days'])
        .map((e) => MonthDayInfo.fromJson(_asMap(e)))
        .toList();
    return (year, monthNum, days);
  }

  Future<void> createPlan({
    required String date,
    required String mealType,
    required int recipeId,
  }) async {
    await _post('/api/calendar/plan', body: {
      'date': date,
      'meal_type': mealType,
      'recipe_id': recipeId,
    });
  }

  Future<void> deletePlan({
    required String date,
    required String mealType,
    int? recipeId,
  }) async {
    // 服务端 recipe_id 只接受 Query 参数：不传则删除该餐全部
    await _delete(
      '/api/calendar/plan',
      query: {
        'date': date,
        'meal_type': mealType,
        if (recipeId != null) 'recipe_id': '$recipeId',
      },
    );
  }

  Future<ShoppingListData> shoppingList(String date) async {
    final data =
        await _get('/api/calendar/shopping-list', query: {'date': date});
    final body = _asMap(data);
    return ShoppingListData(
      items: _asList(body['items'])
          .map((e) => ShoppingItem.fromJson(_asMapLoose(e)))
          .toList(),
      byDay: _asList(body['by_day'])
          .map((e) => ShoppingDay.fromJson(_asMapLoose(e)))
          .toList(),
    );
  }

  Future<Profile> getProfile() async {
    final data = await _get('/api/users/profile');
    return Profile.fromJson(_asMap(data));
  }

  Future<Profile> updateProfile({
    required String displayName,
    String? username,
    required String? avatar,
    String? carouselType,
    int? carouselLimit,
    List<String>? avoidTags,
  }) async {
    final data = await _put('/api/users/profile', body: {
      'display_name': displayName,
      'avatar': avatar,
      'username': ?username,
      'carousel_type': ?carouselType,
      'carousel_limit': ?carouselLimit,
      'avoid_tags': ?avoidTags,
    });
    return Profile.fromJson(_asMap(data));
  }

  Future<User> updateMe(String displayName) async {
    final data = await _put('/api/users/update_me', body: {
      'display_name': displayName,
    });
    return User.fromJson(_asMap(data));
  }

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    await _put('/api/users/me/password', body: {
      'old_password': oldPassword,
      'new_password': newPassword,
    });
  }

  Future<(String, String?)> uploadAvatar({
    required String imagePath,
    String? avatar,
  }) async {
    final data = await _sendMultipart(
      'POST',
      '/api/users/avatar/upload',
      fields: {'avatar': ?avatar},
      files: {'image': imagePath},
    );
    final body = _asMap(data);
    return (
      body['avatar'] as String? ?? '',
      body['avatar_path'] as String?,
    );
  }

  Future<String> uploadImage(String filePath) async {
    final data = await _sendMultipart(
      'POST',
      '/api/upload',
      files: {'file': filePath},
    );
    return _asMap(data)['path'] as String? ?? '';
  }

  Future<Map<String, dynamic>> checkApp({bool force = false}) async {
    final data = await _get(
      '/api/app/check',
      query: {'force': '$force'},
    );
    return _asMap(data);
  }

  Future<(List<Map<String, dynamic>>, List<String>, String)> searchOnlineRecipe(
    String keyword, {
    String? source,
  }) async {
    final data = await _get(
      '/api/recipe-api/search',
      query: {
        'keyword': keyword,
        if (source != null && source.isNotEmpty) 'source': source,
      },
    );
    final body = _asMap(data);
    return (
      _asMapList(body['items']),
      _asStringList(body['en_queries']),
      body['zh_keyword'] as String? ?? '',
    );
  }

  /// 链接导入（豆果/JSON-LD 通用）：POST /api/recipe-api/fetch-url
  Future<Map<String, dynamic>> fetchUrlImport(String url) async {
    final data = await _post('/api/recipe-api/fetch-url', body: {'url': url});
    return _asMap(data);
  }

  /// 拍照 OCR：POST /api/ocr（multipart image），返回识别文本
  Future<String> ocrImage(String filePath) async {
    final data = await _sendMultipart(
      'POST',
      '/api/ocr',
      files: {'file': filePath},
    );
    return _asMap(data)['text'] as String? ?? '';
  }

  Future<(bool, String, List<String>)> translateKeyword(String keyword) async {
    final data = await _get(
      '/api/recipe-api/translate-keyword',
      query: {'keyword': keyword},
    );
    final body = _asMap(data);
    return (
      body['is_chinese'] as bool? ?? false,
      body['zh'] as String? ?? '',
      _asStringList(body['en']),
    );
  }

  Future<Map<String, dynamic>> prepareOnlineRecipe(
    Map<String, dynamic> form,
  ) async {
    final data = await _post('/api/recipe-api/prepare', body: form);
    return _asMap(data);
  }

  Future<Map<String, dynamic>> parsePaste(String text) async {
    final data = await _post('/api/recipe-api/parse-paste', body: {'text': text});
    return _asMap(data);
  }

  // ---------- TTS（服务端 Edge 合成，返回 mp3 字节） ----------

  Future<List<({String key, String label})>> fetchTtsVoices() async {
    final data = await _get('/api/tts/voices');
    return _asList(_asMap(data)['voices'])
        .map((e) {
          final m = _asMapLoose(e);
          return (
            key: (m['key'] ?? '').toString(),
            label: (m['label'] ?? '').toString(),
          );
        })
        .where((v) => v.key.isNotEmpty)
        .toList();
  }

  /// 合成语音 mp3。text 超长时调用方需自行截断（服务端上限 500 字）
  Future<List<int>> synthesizeTts({
    required String text,
    String voice = 'xiaoxiao',
    double rate = 1.0,
    double pitch = 1.0,
  }) {
    return _postBytes('/api/tts', body: {
      'text': text,
      'voice': voice,
      'rate': rate,
      'pitch': pitch,
    });
  }

  Future<List<Map<String, dynamic>>> searchImage({
    required String keyword,
    int page = 1,
    int perPage = 10,
    String? provider,
  }) async {
    final data = await _get(
      '/api/search-image',
      query: {
        'keyword': keyword,
        'page': '$page',
        'per_page': '$perPage',
        if (provider != null && provider.isNotEmpty) 'provider': provider,
      },
    );
    return _asMapList(data);
  }

  String _parseError(http.Response response) {
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is Map<String, dynamic>) {
        final detail = body['detail'];
        if (detail is String && detail.isNotEmpty) return detail;
        if (detail is Map) {
          final msg = detail['msg'];
          if (msg is String && msg.isNotEmpty) return msg;
        }
      }
    } catch (_) {
      return '请求失败 (${response.statusCode})';
    }
    return '请求失败 (${response.statusCode})';
  }
}
