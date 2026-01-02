// lib/services/app_config_service.dart
import 'dart:convert';

import 'api_client.dart';

class ImageUploadPolicy {
  final int maxPhotosPerOuting;
  final int pickerMaxWidth;
  final int pickerMaxHeight;
  final int pickerQuality;
  final int compressQuality;
  final bool saverModeEnabled;
  final String saverReason;

  const ImageUploadPolicy({
    required this.maxPhotosPerOuting,
    required this.pickerMaxWidth,
    required this.pickerMaxHeight,
    required this.pickerQuality,
    required this.compressQuality,
    required this.saverModeEnabled,
    required this.saverReason,
  });

  static const ImageUploadPolicy defaults = ImageUploadPolicy(
    maxPhotosPerOuting: 10,
    pickerMaxWidth: 1440,
    pickerMaxHeight: 1440,
    pickerQuality: 85,
    compressQuality: 75,
    saverModeEnabled: false,
    saverReason: 'default',
  );

  factory ImageUploadPolicy.fromApi(Map<String, dynamic> data) {
    final saver = (data['saverMode'] ?? {}) as Map<String, dynamic>;
    final pol = (data['imageUploadPolicy'] ?? {}) as Map<String, dynamic>;

    int intOr(int? v, int fallback) => (v ?? fallback);

    return ImageUploadPolicy(
      saverModeEnabled: (saver['enabled'] == true),
      saverReason: (saver['reason']?.toString() ?? 'unknown'),
      maxPhotosPerOuting: intOr(
        pol['maxPhotosPerOuting'] as int?,
        defaults.maxPhotosPerOuting,
      ),
      pickerMaxWidth: intOr(
        pol['pickerMaxWidth'] as int?,
        defaults.pickerMaxWidth,
      ),
      pickerMaxHeight: intOr(
        pol['pickerMaxHeight'] as int?,
        defaults.pickerMaxHeight,
      ),
      pickerQuality: intOr(
        pol['pickerQuality'] as int?,
        defaults.pickerQuality,
      ),
      compressQuality: intOr(
        pol['compressQuality'] as int?,
        defaults.compressQuality,
      ),
    );
  }
}

class AppConfigService {
  AppConfigService(this.api);
  final ApiClient api;

  static ImageUploadPolicy? _cachedPolicy;
  static DateTime? _cachedAt;

  Future<ImageUploadPolicy> getImageUploadPolicy({
    Duration cacheFor = const Duration(minutes: 10),
  }) async {
    final now = DateTime.now();
    if (_cachedPolicy != null && _cachedAt != null) {
      if (now.difference(_cachedAt!) < cacheFor) return _cachedPolicy!;
    }

    try {
      final r = await api.get('/api/app/config');
      if (r.statusCode != 200)
        return _cachedPolicy ?? ImageUploadPolicy.defaults;

      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final data = (j['data'] ?? {}) as Map<String, dynamic>;
      final policy = ImageUploadPolicy.fromApi(data);

      _cachedPolicy = policy;
      _cachedAt = now;
      return policy;
    } catch (_) {
      return _cachedPolicy ?? ImageUploadPolicy.defaults;
    }
  }
}
