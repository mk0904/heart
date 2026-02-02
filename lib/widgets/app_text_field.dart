import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// Production-ready, consistent text input field used throughout the app
class AppTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? label;
  final String? hintText;
  final IconData? prefixIcon;
  final IconData? suffixIcon;
  final VoidCallback? onSuffixTap;
  final TextInputType? keyboardType;
  final bool obscureText;
  final bool enabled;
  final int? maxLines;
  final int? maxLength;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final void Function()? onTap;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  final void Function(String)? onSubmitted;
  final List<TextInputFormatter>? inputFormatters;
  final bool readOnly;
  final Color? fillColor;
  final EdgeInsetsGeometry? contentPadding;

  const AppTextField({
    super.key,
    this.controller,
    this.label,
    this.hintText,
    this.prefixIcon,
    this.suffixIcon,
    this.onSuffixTap,
    this.keyboardType,
    this.obscureText = false,
    this.enabled = true,
    this.maxLines = 1,
    this.maxLength,
    this.validator,
    this.onChanged,
    this.onTap,
    this.focusNode,
    this.textInputAction,
    this.onSubmitted,
    this.inputFormatters,
    this.readOnly = false,
    this.fillColor,
    this.contentPadding,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.text,
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(height: AppTheme.spacingXS + 2),
        ],
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscureText,
          enabled: enabled,
          maxLines: maxLines,
          maxLength: maxLength,
          validator: validator,
          onChanged: onChanged,
          onTap: onTap,
          focusNode: focusNode,
          textInputAction: textInputAction,
          onFieldSubmitted: onSubmitted,
          inputFormatters: inputFormatters,
          readOnly: readOnly,
          style: TextStyle(
            fontSize: 16,
            color: enabled ? AppTheme.text : AppTheme.textSecondary,
            fontWeight: FontWeight.w400,
          ),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: const TextStyle(
              color: AppTheme.textLight,
              fontSize: 16,
            ),
            prefixIcon: prefixIcon != null
                ? Icon(
                    prefixIcon,
                    size: 20,
                    color: AppTheme.textSecondary,
                  )
                : null,
            suffixIcon: suffixIcon != null
                ? GestureDetector(
                    onTap: onSuffixTap,
                    child: Icon(
                      suffixIcon,
                      size: 20,
                      color: AppTheme.textSecondary,
                    ),
                  )
                : null,
            filled: true,
            fillColor: fillColor ?? AppTheme.backgroundDark,
            contentPadding: contentPadding ??
                EdgeInsets.symmetric(
                  horizontal: prefixIcon != null ? AppTheme.spacingMD : AppTheme.spacingLG,
                  vertical: AppTheme.spacingMD + 2,
                ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusBase),
              borderSide: const BorderSide(color: AppTheme.borderLight, width: 1),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusBase),
              borderSide: const BorderSide(color: AppTheme.borderLight, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusBase),
              borderSide: const BorderSide(color: AppTheme.primary, width: 2),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusBase),
              borderSide: const BorderSide(color: AppTheme.borderLight, width: 1),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusBase),
              borderSide: const BorderSide(color: AppTheme.error, width: 1.5),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusBase),
              borderSide: const BorderSide(color: AppTheme.error, width: 2),
            ),
            errorStyle: const TextStyle(
              fontSize: 12,
              color: AppTheme.error,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

/// Multi-line text field for longer content
class AppTextArea extends StatelessWidget {
  final TextEditingController? controller;
  final String? label;
  final String? hintText;
  final IconData? prefixIcon;
  final int? maxLines;
  final int? maxLength;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final bool enabled;

  const AppTextArea({
    super.key,
    this.controller,
    this.label,
    this.hintText,
    this.prefixIcon,
    this.maxLines = 4,
    this.maxLength,
    this.validator,
    this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.text,
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(height: AppTheme.spacingXS + 2),
        ],
        Container(
          decoration: BoxDecoration(
            color: AppTheme.backgroundDark,
            borderRadius: BorderRadius.circular(AppTheme.radiusBase),
            border: Border.all(color: AppTheme.borderLight, width: 1),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (prefixIcon != null) ...[
                Padding(
                  padding: const EdgeInsets.only(
                    left: AppTheme.spacingMD,
                    top: AppTheme.spacingMD + 2,
                  ),
                  child: Icon(
                    prefixIcon,
                    size: 20,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
              Expanded(
                child: TextFormField(
                  controller: controller,
                  maxLines: maxLines,
                  maxLength: maxLength,
                  validator: validator,
                  onChanged: onChanged,
                  enabled: enabled,
                  style: TextStyle(
                    fontSize: 16,
                    color: enabled ? AppTheme.text : AppTheme.textSecondary,
                    fontWeight: FontWeight.w400,
                  ),
                  decoration: InputDecoration(
                    hintText: hintText,
                    hintStyle: const TextStyle(
                      color: AppTheme.textLight,
                      fontSize: 16,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(AppTheme.spacingMD + 2),
                    counterText: '',
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
