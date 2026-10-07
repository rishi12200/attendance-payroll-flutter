int? rupeesStringToPaise(String value) {
  final input = value.trim();
  if (input.isEmpty || input.startsWith('-') || input.startsWith('+')) {
    return null;
  }

  final parts = input.split('.');
  if (parts.length > 2) return null;
  final rupees = parts[0];
  final paise = parts.length == 2 ? parts[1] : '';
  if (rupees.isEmpty ||
      (parts.length == 2 && (paise.isEmpty || paise.length > 2)) ||
      (paise.isNotEmpty && !RegExp(r'^\d+$').hasMatch(paise))) {
    return null;
  }

  final validGroupedRupees =
      RegExp(r'^\d+$').hasMatch(rupees) ||
      RegExp(r'^\d{1,2}(,\d{2})*,\d{3}$').hasMatch(rupees);
  if (!validGroupedRupees) return null;

  final wholeRupees = int.tryParse(rupees.replaceAll(',', ''));
  final fractionalPaise = int.tryParse(paise.padRight(2, '0')) ?? 0;
  if (wholeRupees == null) return null;
  final totalPaise = wholeRupees * 100 + fractionalPaise;
  if (totalPaise <= 0) return null;
  return totalPaise;
}

String paiseToDisplay(int paise) {
  if (paise < 0) {
    throw ArgumentError.value(paise, 'paise', 'Must not be negative.');
  }
  final rupees = (paise ~/ 100).toString();
  final grouped = _groupIndianDigits(rupees);
  final cents = (paise % 100).toString().padLeft(2, '0');
  return '₹$grouped.$cents';
}

String _groupIndianDigits(String digits) {
  if (digits.length <= 3) return digits;
  final lastThree = digits.substring(digits.length - 3);
  var leading = digits.substring(0, digits.length - 3);
  final groups = <String>[];
  while (leading.length > 2) {
    groups.insert(0, leading.substring(leading.length - 2));
    leading = leading.substring(0, leading.length - 2);
  }
  groups.insert(0, leading);
  return '${groups.join(',')},$lastThree';
}
