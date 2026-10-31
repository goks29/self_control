import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
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
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: AppSpacing.sheetPadding,
      decoration: const BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.xxl)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
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
                    borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              const Center(
                child: Icon(
                  Icons.accessibility_new_rounded,
                  size: 44,
                  color: AppColors.brown,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Aktivasi Layanan Aksesibilitas',
                textAlign: TextAlign.center,
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Aplikasi Self-Control memerlukan izin Layanan Aksesibilitas untuk mendeteksi kapan aplikasi yang dibatasi dibuka, sehingga pemblokiran dapat berjalan secara otomatis tanpa menguras baterai.',
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.lg),
              _buildStepRow(context, 1, 'Tekan tombol "Buka Pengaturan" di bawah.'),
              const SizedBox(height: AppSpacing.sm),
              _buildStepRow(context, 2, 'Cari dan pilih "Self-Control" pada menu Aksesibilitas.'),
              const SizedBox(height: AppSpacing.sm),
              _buildStepRow(context, 3, 'Aktifkan toggle switch (Izinkan / On).'),
              const SizedBox(height: AppSpacing.sm),
              _buildStepRow(context, 4, 'Kembali ke aplikasi ini untuk menyelesaikan aktivasi.'),
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                text: 'Buka Pengaturan Aksesibilitas',
                onPressed: () async {
                  Navigator.of(context).pop();
                  await effectiveChannel.openAccessibilitySettings();
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                text: 'Nanti Saja',
                variant: AppButtonVariant.text,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepRow(BuildContext context, int number, String instruction) {
    final textTheme = Theme.of(context).textTheme;

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
            style: textTheme.labelMedium?.copyWith(
              color: AppColors.cream,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            instruction,
            style: textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}
