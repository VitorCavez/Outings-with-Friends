// lib/models/outing_image.dart
class OutingImage {
  final String id;
  final String imageUrl;
  final String provider; // cloudinary/unsplash/external
  final int? width;
  final int? height;
  final DateTime? createdAt;

  OutingImage({
    required this.id,
    required this.imageUrl,
    required this.provider,
    this.width,
    this.height,
    this.createdAt,
  });

  factory OutingImage.fromJson(Map<String, dynamic> j) {
    return OutingImage(
      id: j['id'],
      imageUrl: j['imageUrl'],
      provider: j['provider'] ?? j['imageSource'] ?? 'external',
      width: j['width'],
      height: j['height'],
      createdAt: j['createdAt'] != null ? DateTime.parse(j['createdAt']) : null,
    );
  }
}
