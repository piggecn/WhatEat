import 'package:flutter/material.dart';

import '../models/inventory.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../widgets/state_views.dart';

/// 家里剩啥：食材库存，随机推荐「仅用现有食材」的数据来源（对齐网页 /inventory）
class InventoryScreen extends StatefulWidget {
  final ApiClient api;

  const InventoryScreen({super.key, required this.api});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _unitController = TextEditingController();

  List<InventoryItem> _items = [];
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _unitController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await widget.api.fetchInventory();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _items = [];
        _loading = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('加载失败，请下拉重试')));
    }
  }

  Future<void> _add() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('食材名要填')));
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.api.addInventory(
        name: name,
        amount: _amountController.text.trim(),
        unit: _unitController.text.trim(),
      );
      if (!mounted) return;
      _nameController.clear();
      _amountController.clear();
      _unitController.clear();
      FocusScope.of(context).unfocus();
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('添加失败，请重试')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _delete(InventoryItem item) async {
    setState(() => _items = [
          for (final it in _items)
            if (it.id != item.id) it,
        ]);
    try {
      await widget.api.deleteInventory(item.id);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('删除失败，已恢复')));
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('家里剩啥')),
      body: _loading
          ? const LoadingState(message: '加载中...')
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('添加食材', style: AppTypography.h3),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller: _nameController,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    hintText: '食材名（如：鸡蛋）',
                                  ),
                                  onSubmitted: (_) => _add(),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _amountController,
                                  textInputAction: TextInputAction.next,
                                  keyboardType: TextInputType.text,
                                  decoration: const InputDecoration(
                                      hintText: '数量'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _unitController,
                                  textInputAction: TextInputAction.done,
                                  decoration: const InputDecoration(
                                      hintText: '单位'),
                                  onSubmitted: (_) => _add(),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed:
                                  _submitting ? null : _add,
                              icon: _submitting
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.add, size: 18),
                              label: const Text('加入库存'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 48),
                      child: EmptyState(
                        icon: Icons.kitchen_outlined,
                        title: '库存是空的',
                        subtitle: '录入现有食材，随机推荐就能「仅用现有食材」',
                      ),
                    )
                  else
                    Card(
                      margin: EdgeInsets.zero,
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (final item in _items)
                            ListTile(
                              leading: const Icon(Icons.egg_outlined,
                                  color: AppColors.primary),
                              title: Text(
                                item.name,
                                style: AppTypography.body.copyWith(
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (item.display.isNotEmpty)
                                    Text(
                                      item.display,
                                      style: AppTypography.caption.copyWith(
                                        color: theme
                                            .colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  IconButton(
                                    icon: const Icon(Icons.close, size: 18),
                                    tooltip: '删除',
                                    onPressed: () => _delete(item),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
