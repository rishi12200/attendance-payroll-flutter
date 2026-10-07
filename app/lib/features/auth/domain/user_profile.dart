enum UserRole { admin, employee }

class UserProfile {
  const UserProfile({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
  });

  final String uid;
  final String name;
  final String email;
  final UserRole role;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final roleName = json['role'];
    final role = switch (roleName) {
      'admin' => UserRole.admin,
      'employee' => UserRole.employee,
      _ => null,
    };
    final uid = json['uid'];
    final name = json['name'];
    final email = json['email'];

    if (role == null ||
        uid is! String ||
        name is! String ||
        email is! String) {
      throw const FormatException('The server returned an invalid user profile.');
    }

    return UserProfile(uid: uid, name: name, email: email, role: role);
  }
}
