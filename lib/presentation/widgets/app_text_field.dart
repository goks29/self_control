import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants/app_colors.dart';

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    this.label,
    this.hint,
    this.controller,
    this.validator,
    this.onChanged,
    this.obscureText = false,
    this.keyboardType,
    this.maxLines = 1,
    this.minLines,
    this.prefixIcon,
    this.suffixIcon,
    this.enabled = true,
    this.errorText,
    this.autofocus = false,
    this.focusNode,
    this.onFieldSubmitted,
    this.maxLength,
    this.inputFormatters,
  });

  final String? label;
  final String? hint;
  final TextEditingController? controller;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final bool obscureText;
  final TextInputType? keyboardType;
  final int maxLines;
  final int? minLines;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final bool enabled;
  final String? errorText;
  final bool autofocus;
  final FocusNode? focusNode;
  final ValueChanged<String>? onFieldSubmitted;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final field = TextFormField(
      controller: controller,
      validator: validator,
      onChanged: onChanged,
      obscureText: obscureText,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
      minLines: minLines,
      maxLength: maxLength,
      enabled: enabled,
      autofocus: autofocus,
      focusNode: focusNode,
      onFieldSubmitted: onFieldSubmitted,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: AppColors.darkGreen,
        fontWeight: FontWeight.w400,
      ),
      decoration: InputDecoration(
        hintText: hint,
        errorText: errorText,
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
      ),
    );

    if (label == null) {
      return field;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label!,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.darkGreen,
          ),
        ),
        const SizedBox(height: 6),
        field,
      ],
    );
  }
}
