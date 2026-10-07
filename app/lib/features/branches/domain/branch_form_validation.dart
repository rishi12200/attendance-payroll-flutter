String? validateLatitude(String? value) {
  final number = double.tryParse(value?.trim() ?? '');
  if (number == null || !number.isFinite || number < -90 || number > 90) {
    return 'Enter a latitude from -90 to 90.';
  }
  return null;
}
String? validateLongitude(String? value) {
  final number = double.tryParse(value?.trim() ?? '');
  if (number == null || !number.isFinite || number < -180 || number > 180) {
    return 'Enter a longitude from -180 to 180.';
  }
  return null;
}

String? validateRadius(String? value) {
  final radius = int.tryParse(value?.trim() ?? '');
  if (radius == null || radius < 20 || radius > 1000) {
    return 'Enter an integer radius from 20 to 1000 metres.';
  }
  return null;
}
