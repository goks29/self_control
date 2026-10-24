import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

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
    this.height = 48.0,
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
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text(text),
        ],
      );
    } else {
      content = Text(text);
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: content,
          ),
        );
    }
  }
}
