import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../widgets/app_button.dart';

class SessionExpiredModal extends StatelessWidget {
  const SessionExpiredModal({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const SessionExpiredModal(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.cream,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.timer_off_outlined,
              size: 56,
              color: AppColors.brown,
            ),
            const SizedBox(height: 16),
            const Text(
              'Akses Berakhir',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.darkGreen,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Waktu akses sementara telah berakhir. Aplikasi kembali dibatasi.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: AppColors.darkGreen,
              ),
            ),
            const SizedBox(height: 24),
            AppButton(
              text: 'Kembali',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
