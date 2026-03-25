import 'package:flutter/services.dart';

String formatPrice(double price) {
  final parts = price.toStringAsFixed(0).split('');
  final buffer = StringBuffer();
  int count = 0;
  for (int i = parts.length - 1; i >= 0; i--) {
    buffer.write(parts[i]);
    count++;
    if (count % 3 == 0 && i != 0) {
      buffer.write(',');
    }
  }
  return buffer.toString().split('').reversed.join();
}

class PriceInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    final numericString = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');

    final buffer = StringBuffer();
    for (int i = 0; i < numericString.length; i++) {
      if (i > 0 && (numericString.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(numericString[i]);
    }

    final formattedString = buffer.toString();

    return TextEditingValue(
      text: formattedString,
      selection: TextSelection.collapsed(offset: formattedString.length),
    );
  }
}
