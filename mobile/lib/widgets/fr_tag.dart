import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class FrTag extends StatelessWidget {
  final String label;
  final Color? background;
  final Color? foreground;
  final EdgeInsetsGeometry padding;

  const FrTag(
    this.label, {
    super.key,
    this.background,
    this.foreground,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: background ?? theme.colorScheme.primary.withAlpha(24),
        borderRadius: BorderRadius.circular(AppRadius.small),
      ),
      child: Text(
        label,
        style: AppTypography.tag.copyWith(
          color: foreground ?? theme.colorScheme.primary,
        ),
      ),
    );
  }
}
