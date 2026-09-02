import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class RecipeImagePlaceholder extends StatelessWidget {
  final double iconSize;

  const RecipeImagePlaceholder({super.key, this.iconSize = 40});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.success],
        ),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.restaurant,
        size: iconSize,
        color: Colors.white.withAlpha(220),
      ),
    );
  }
}

class RecipeImage extends StatelessWidget {
  final String? url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final double iconSize;

  const RecipeImage({
    super.key,
    this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.iconSize = 40,
  });

  @override
  Widget build(BuildContext context) {
    final Widget image = (url == null || url!.isEmpty)
        ? RecipeImagePlaceholder(iconSize: iconSize)
        : Image.network(
            url!,
            fit: fit,
            errorBuilder: (_, _, _) => RecipeImagePlaceholder(iconSize: iconSize),
          );
    Widget result = image;
    if (width != null || height != null) {
      result = SizedBox(width: width, height: height, child: result);
    }
    if (borderRadius != null) {
      result = ClipRRect(borderRadius: borderRadius!, child: result);
    }
    return result;
  }
}
