import 'package:flutter/material.dart';
import '../core/theme.dart';

class ShellTextField extends StatefulWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final bool obscure;
  final TextInputType keyboardType;
  final String? Function(String?)? validator;

  const ShellTextField({
    required this.label,
    required this.hint,
    required this.controller,
    this.obscure = false,
    this.keyboardType = TextInputType.text,
    this.validator,
    super.key,
  });

  @override
  State<ShellTextField> createState() => _ShellTextFieldState();
}

class _ShellTextFieldState extends State<ShellTextField> {
  bool _touched = false; // user has left the field at least once
  String? _liveError;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (!_touched) return; // don't validate before first blur
    setState(() => _liveError = widget.validator?.call(widget.controller.text));
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
            if (!hasFocus) {
              setState(() {
                _touched = true;
                _liveError = widget.validator?.call(widget.controller.text);
              });
            }
          },
          child: TextFormField(
            controller: widget.controller,
            obscureText: widget.obscure,
            validator: widget.validator,
            keyboardType: widget.keyboardType,
            style: const TextStyle(
              fontFamily: 'DM Sans',
              fontSize: 17,
              color: Color(0xFF222222),
            ),
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: const TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 17,
                color: Color(0xFF787878),
              ),
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
