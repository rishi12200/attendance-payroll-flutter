enum BranchStatus { active, inactive }

class Branch {
  const Branch({
    required this.id,
    required this.name,
    required this.state,
    required this.lat,
    required this.lng,
    required this.radiusMeters,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.address,
    this.editedBy,
  });

  final String id;
  final String name;
  final String? address;
  final String state;
  final double lat;
  final double lng;
  final int radiusMeters;
  final BranchStatus status;
  final String createdAt;
  final String updatedAt;
  final String? editedBy;

  factory Branch.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final state = json['state'];
    final lat = json['lat'];
    final lng = json['lng'];
    final radius = json['radiusMeters'];
    final status = switch (json['status']) {
      'active' => BranchStatus.active,
      'inactive' => BranchStatus.inactive,
      _ => null,
    };
    final createdAt = json['createdAt'];
    final updatedAt = json['updatedAt'];
    if (id is! String ||
        name is! String ||
        state is! String ||
        lat is! num ||
        lng is! num ||
        radius is! int ||
        status == null ||
        createdAt is! String ||
        updatedAt is! String) {
      throw const FormatException('The server returned an invalid branch.');
    }
    return Branch(
      id: id,
      name: name,
      address: _optionalString(json['address']),
      state: state,
      lat: lat.toDouble(),
      lng: lng.toDouble(),
      radiusMeters: radius,
      status: status,
      createdAt: createdAt,
      updatedAt: updatedAt,
      editedBy: _optionalString(json['editedBy']),
    );
  }
}

String? _optionalString(Object? value) {
  if (value == null) return null;
  if (value is String) return value;
  throw const FormatException('The server returned an invalid branch.');
}
