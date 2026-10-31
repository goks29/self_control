import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';

enum AppButtonVariant { primary, secondary, outlineBrown, text }

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.text,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.isLoading = false,
    this.icon,
    this.isFullWidth = true,
    this.height = AppSpacing.buttonHeight,
  });

  final String text;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final bool isLoading;
  final IconData? icon;
  final bool isFullWidth;
  final double height;

  @override
  Widget build(BuildContext context) {
    final effectiveOnPressed = isLoading ? null : onPressed;

    final Color textColor;
    switch (variant) {
      case AppButtonVariant.primary:
        textColor = effectiveOnPressed == null
            ? AppColors.white.withValues(alpha: 0.8)
            : AppColors.white;
        break;
      case AppButtonVariant.secondary:
      case AppButtonVariant.text:
        textColor = effectiveOnPressed == null
            ? AppColors.darkGreen.withValues(alpha: 0.4)
            : AppColors.darkGreen;
        break;
      case AppButtonVariant.outlineBrown:
        textColor = effectiveOnPressed == null
            ? AppColors.brown.withValues(alpha: 0.4)
            : AppColors.brown;
        break;
    }

    final TextStyle textStyle = (Theme.of(context).textTheme.labelLarge ??
            const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))
        .copyWith(
      color: textColor,
      fontWeight: FontWeight.w600,
    );

    Widget content;
    if (isLoading) {
      final spinnerColor = variant == AppButtonVariant.primary
          ? AppColors.white
          : (variant == AppButtonVariant.outlineBrown ? AppColors.brown : AppColors.darkGreen);
      content = SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          valueColor: AlwaysStoppedAnimation<Color>(spinnerColor),
        ),
      );
    } else if (icon != null) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: textColor),
          const SizedBox(width: AppSpacing.sm),
          Text(
            text,
            style: textStyle,
            textAlign: TextAlign.center,
          ),
        ],
      );
    } else {
      content = Text(
        text,
        style: textStyle,
        textAlign: TextAlign.center,
      );
    }

    switch (variant) {
      case AppButtonVariant.primary:
        return SizedBox(
          width: isFullWidth ? double.infinity : null,
          height: height,
          child: ElevatedButton(
            onPressed: effectiveOnPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brown,
              foregroundColor: AppColors.white,
              disabledBackgroundColor: AppColors.brown.withValues(alpha: 0.4),
              disabledForegroundColor: AppColors.white.withValues(alpha: 0.8),
              elevation: 0,
              padding: EdgeInsets.symmetric(
                horizontal: isFullWidth ? AppSpacing.xxl : AppSpacing.lg,
                vertical: 0,
              ),
              minimumSize: Size(0, height),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
              ),
              textStyle: textStyle,
            ),
            child: content,
          ),
        );

      case AppButtonVariant.secondary:
        return SizedBox(
          width: isFullWidth ? double.infinity : null,
          height: height,
          child: OutlinedButton(
            onPressed: effectiveOnPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.darkGreen,
              disabledForegroundColor: AppColors.darkGreen.withValues(alpha: 0.4),
              side: BorderSide(
                color: effectiveOnPressed == null
                    ? AppColors.darkGreen.withValues(alpha: 0.3)
                    : AppColors.darkGreen,
                width: 1.5,
              ),
              padding: EdgeInsets.symmetric(
                horizontal: isFullWidth ? AppSpacing.xxl : AppSpacing.lg,
                vertical: 0,
              ),
              minimumSize: Size(0, height),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
              ),
              textStyle: textStyle,
            ),
            child: content,
          ),
        );

      case AppButtonVariant.outlineBrown:
        return SizedBox(
          width: isFullWidth ? double.infinity : null,
          height: height,
          child: OutlinedButton(
            onPressed: effectiveOnPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.brown,
              disabledForegroundColor: AppColors.brown.withValues(alpha: 0.4),
              side: BorderSide(
                color: effectiveOnPressed == null
                    ? AppColors.brown.withValues(alpha: 0.3)
                    : AppColors.brown,
                width: 1.5,
              ),
              padding: EdgeInsets.symmetric(
                horizontal: isFullWidth ? AppSpacing.xxl : AppSpacing.lg,
                vertical: 0,
              ),
              minimumSize: Size(0, height),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
              ),
              textStyle: textStyle,
            ),
            child: content,
          ),
        );

      case AppButtonVariant.text:
        return SizedBox(
          width: isFullWidth ? double.infinity : null,
          height: height,
          child: TextButton(
            onPressed: effectiveOnPressed,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.darkGreen,
              disabledForegroundColor: AppColors.darkGreen.withValues(alpha: 0.4),
              padding: EdgeInsets.symmetric(
                horizontal: isFullWidth ? AppSpacing.xxl : AppSpacing.lg,
                vertical: 0,
              ),
              minimumSize: Size(0, height),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
              ),
              textStyle: textStyle,
            ),
            child: content,
          ),
        );
    }
  }
}
