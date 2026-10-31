import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = AppSpacing.cardPadding,
    this.margin,
    this.color,
    this.onTap,
    this.borderRadius = AppSpacing.cardRadius,
    this.border,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final VoidCallback? onTap;
  final double borderRadius;
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? AppColors.peach;
    final radius = BorderRadius.circular(borderRadius);

    Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: effectiveColor,
        borderRadius: radius,
        border: border ?? Border.all(color: AppColors.cardBorder, width: 1),
      ),
      child: child,
    );

    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: content,
        ),
      );
    }

    if (margin != null) {
      content = Padding(
        padding: margin!,
        child: content,
      );
    }

    return content;
  }
}
