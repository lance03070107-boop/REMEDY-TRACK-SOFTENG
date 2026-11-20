import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Reusable Material 3 text field with 48dp minimum touch target, input formatters,
/// unit suffixes, helper range text, and accessible labeling.
class CustomTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? helperText;
  final String? suffixText;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final bool readOnly;
  final bool enabled;
  final TextInputType keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;
  final int maxLines;
  final int? maxLength;
  final MaxLengthEnforcement? maxLengthEnforcement;

  const CustomTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.helperText,
    this.suffixText,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.readOnly = false,
    this.enabled = true,
    this.keyboardType = TextInputType.text,
    this.textInputAction,
    this.autofillHints,
    this.inputFormatters,
    this.validator,
    this.onChanged,
    this.onFieldSubmitted,
    this.maxLines = 1,
    this.maxLength,
    this.maxLengthEnforcement,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          readOnly: readOnly,
          enabled: enabled,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          autofillHints: autofillHints,
          inputFormatters: inputFormatters,
          maxLines: maxLines,
          maxLength: maxLength,
          maxLengthEnforcement: maxLengthEnforcement,
          validator: validator,
          onChanged: onChanged,
          onFieldSubmitted: onFieldSubmitted,
          decoration: InputDecoration(
            hintText: hint,
            helperText: helperText,
            helperMaxLines: 2,
            errorMaxLines: 2,
            suffixText: suffixText,
            prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
            suffixIcon: suffixIcon,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ],
    );
  }
}
