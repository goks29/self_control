import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/platform/blocking_platform_channel.dart';
import '../../widgets/app_button.dart';

class PermissionGuideModal extends StatelessWidget {
  const PermissionGuideModal({
    super.key,
    this.platformChannel,
  });

  final BlockingPlatformChannel? platformChannel;

  static Future<void> show(
    BuildContext context, {
    BlockingPlatformChannel? platformChannel,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PermissionGuideModal(platformChannel: platformChannel),
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveChannel = platformChannel ?? BlockingPlatformChannel();

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      decoration: const BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.peach,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Center(
              child: Icon(
                Icons.accessibility_new_rounded,
                size: 44,
                color: AppColors.brown,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Aktivasi Layanan Aksesibilitas',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.darkGreen,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Aplikasi Self-Control memerlukan izin Layanan Aksesibilitas untuk mendeteksi kapan aplikasi yang dibatasi dibuka, sehingga pemblokiran dapat berjalan secara otomatis tanpa menguras baterai.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: AppColors.darkGreen,
              ),
            ),
            const SizedBox(height: 24),
            _buildStepRow(1, 'Tekan tombol "Buka Pengaturan" di bawah.'),
            const SizedBox(height: 12),
            _buildStepRow(2, 'Cari dan pilih "Self-Control" pada menu Aksesibilitas.'),
            const SizedBox(height: 12),
            _buildStepRow(3, 'Aktifkan toggle switch (Izinkan / On).'),
            const SizedBox(height: 12),
            _buildStepRow(4, 'Kembali ke aplikasi ini untuk menyelesaikan aktivasi.'),
            const SizedBox(height: 28),
            AppButton(
              text: 'Buka Pengaturan Aksesibilitas',
              onPressed: () async {
                Navigator.of(context).pop();
                await effectiveChannel.openAccessibilitySettings();
              },
            ),
            const SizedBox(height: 8),
            AppButton(
              text: 'Nanti Saja',
              variant: AppButtonVariant.text,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepRow(int number, String instruction) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.brown,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$number',
            style: const TextStyle(
              color: AppColors.cream,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            instruction,
            style: const TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AppColors.darkGreen,
            ),
          ),
        ),
      ],
    );
  }
}
