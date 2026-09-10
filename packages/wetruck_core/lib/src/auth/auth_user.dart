import 'dart:convert';

/// Shape used by the Next.js shipper app — kept identical so the same
/// `wetruck_user` secure-storage payload stays meaningful across rewrites.
class AuthUser {
  const AuthUser({
    required this.email,
    required this.role,
    this.id,
    this.name,
  });

  /// The login response doesn't echo back a stable id, so this is nullable
  /// and only populated when the backend returns one (e.g. via /auth/me).
  final String? id;
  final String email;
  final String role;
  final String? name;

  AuthUser copyWith({String? id, String? email, String? role, String? name}) {
    return AuthUser(
      id: id ?? this.id,
      email: email ?? this.email,
      role: role ?? this.role,
      name: name ?? this.name,
    );
  }

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'email': email,
        'role': role,
        if (name != null) 'name': name,
      };

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id']?.toString(),
      email: json['email'] as String,
      role: json['role'] as String? ?? json['user_type'] as String? ?? '',
      name: json['name'] as String?,
    );
  }

  String encode() => jsonEncode(toJson());

  static AuthUser? tryDecode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return AuthUser.fromJson(decoded);
    } catch (_) {}
    return null;
  }
}
