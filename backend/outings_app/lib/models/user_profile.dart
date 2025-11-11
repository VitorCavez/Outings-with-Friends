// lib/models/user_profile.dart
class UserProfile {
  final String id;
  final String fullName;
  final String? username;
  final String? bio;
  final String? profilePhotoUrl;
  final String? homeLocation;
  final bool isProfilePublic;
  final int outingScore;
  final List<String> badges;

  UserProfile({
    required this.id,
    required this.fullName,
    this.username,
    this.bio,
    this.profilePhotoUrl,
    this.homeLocation,
    required this.isProfilePublic,
    required this.outingScore,
    required this.badges,
  });

  factory UserProfile.fromJson(Map<String, dynamic> j) {
    final u = j['user'] ?? j; // handle /profile shape and direct
    return UserProfile(
      id: u['id'],
      fullName: u['fullName'],
      username: u['username'],
      bio: u['bio'],
      profilePhotoUrl: u['profilePhotoUrl'],
      homeLocation: u['homeLocation'],
      isProfilePublic: u['isProfilePublic'] ?? true,
      outingScore: u['outingScore'] ?? 0,
      badges: (u['badges'] as List?)?.map((e) => '$e').toList() ?? const [],
    );
  }
}
