import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import 'app_button.dart';

class RevokedPermissionBanner extends StatelessWidget {
  const RevokedPermissionBanner({
    super.key,
    required this.onFixPressed,
  });

  final VoidCallback onFixPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.peach,
        border: Border(
          bottom: BorderSide(
            color: AppColors.brown.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 360;

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: AppColors.brown,
                      size: 28,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Izin Aksesibilitas Dicabut',
                            style: textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Layanan pemblokiran nonaktif. Aktifkan kembali agar perlindungan fokus berjalan.',
                            style: textTheme.bodySmall?.copyWith(
                              color: AppColors.darkGreen,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerRight,
                  child: AppButton(
                    text: 'Aktifkan',
                    isFullWidth: false,
                    height: AppSpacing.buttonHeightCompact,
                    onPressed: onFixPressed,
                  ),
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: AppColors.brown,
                size: 28,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Izin Aksesibilitas Dicabut',
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Layanan pemblokiran nonaktif. Aktifkan kembali agar perlindungan fokus berjalan.',
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.darkGreen,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              AppButton(
                text: 'Aktifkan',
                isFullWidth: false,
                height: AppSpacing.buttonHeightCompact,
                onPressed: onFixPressed,
              ),
            ],
          );
        },
      ),
    );
  }
}
