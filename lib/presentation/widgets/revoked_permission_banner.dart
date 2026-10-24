import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import 'app_button.dart';

class RevokedPermissionBanner extends StatelessWidget {
  const RevokedPermissionBanner({
    super.key,
    required this.onFixPressed,
  });

  final VoidCallback onFixPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.peach,
        border: Border(
          bottom: BorderSide(
            color: AppColors.brown.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: AppColors.brown,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text(
                  'Izin Aksesibilitas Dicabut',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.darkGreen,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Layanan pemblokiran nonaktif. Aktifkan kembali agar perlindungan fokus berjalan.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: AppColors.darkGreen,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          AppButton(
            text: 'Aktifkan',
            isFullWidth: false,
            height: 36,
            onPressed: onFixPressed,
          ),
        ],
      ),
    );
  }
}
