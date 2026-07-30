import 'package:flutter/material.dart';
import '../core/theme.dart';

class ShellDropdownField<T> extends StatefulWidget {
  final String label;
  final String hint;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final String? Function(T?)? validator;

  const ShellDropdownField({
    required this.label,
    required this.hint,
    required this.value,
    required this.items,
    required this.onChanged,
    this.validator,
    super.key,
  });

  @override
  State<ShellDropdownField<T>> createState() => _ShellDropdownFieldState<T>();
}

class _ShellDropdownFieldState<T> extends State<ShellDropdownField<T>> {
  bool _touched = false;
  String? _liveError;

  void _validate() {
    setState(() {
      _touched = true;
      _liveError = widget.validator?.call(widget.value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasError = _liveError != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
            fontFamily: 'DM Sans',
            fontWeight: FontWeight.w700,
            fontSize: 17,
            color: Color(0xFF232323),
          ),
        ),
        const SizedBox(height: 7),
        Focus(
          onFocusChange: (hasFocus) {
            if (!hasFocus) _validate();
          },
          child: DropdownButtonFormField<T>(
            initialValue: widget.value,
            isExpanded: true,
            items: widget.items,
            onChanged: (value) {
              widget.onChanged(value);

              if (_touched) {
                setState(() {
                  _liveError = widget.validator?.call(value);
                });
              }
            },
            validator: widget.validator,
            style: const TextStyle(
              fontFamily: 'DM Sans',
              fontSize: 17,
              color: Color(0xFF222222),
            ),
            hint: Text(
              widget.hint,
              style: const TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 17,
                color: Color(0xFF787878),
              ),
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFFF1F1F1),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 11,
              ),
              errorStyle: const TextStyle(height: 0, fontSize: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: hasError
                      ? const Color(0xFFC0392B)
                      : AppColors.inputBorder,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: hasError
                      ? const Color(0xFFC0392B)
                      : AppColors.inputBorder,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: hasError
                      ? const Color(0xFFC0392B)
                      : AppColors.gradientStart,
                  width: 1.5,
                ),
              ),
            ),
          ),
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(
              _liveError!,
              style: const TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 12,
                color: Color(0xFFC0392B),
              ),
            ),
          ),
      ],
    );
  }
}
