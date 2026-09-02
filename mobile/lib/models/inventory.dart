/// 库存条目（家里剩啥）：GET /api/inventory 返回 {id, name, amount, unit}
class InventoryItem {
  final int id;
  final String name;
  final String? amount;
  final String? unit;

  const InventoryItem({
    required this.id,
    required this.name,
    this.amount,
    this.unit,
  });

  factory InventoryItem.fromJson(Map<String, dynamic> json) {
    return InventoryItem(
      id: json['id'] is num ? (json['id'] as num).toInt() : 0,
      name: json['name'] as String? ?? '',
      amount: json['amount'] as String?,
      unit: json['unit'] as String?,
    );
  }

  String get display =>
      [if (amount != null && amount!.isNotEmpty) amount!, if (unit != null && unit!.isNotEmpty) unit!]
          .join(' ');
}
