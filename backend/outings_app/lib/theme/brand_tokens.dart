import 'package:flutter/material.dart';

/// Semantic brand colors (not raw hex sprinkled around the app)
@immutable
class BrandColors extends ThemeExtension<BrandColors> {
  final Color success;
  final Color warning;
  final Color info;
  final Color danger;
  final Color elevatedBg;

  const BrandColors({
    required this.success,
    required this.warning,
    required this.info,
    required this.danger,
    required this.elevatedBg,
  });

  factory BrandColors.light() => const BrandColors(
    success: Color(0xFF2E7D32),
    warning: Color(0xFFF9A825),
    info: Color(0xFF0277BD),
    danger: Color(0xFFC62828),
    elevatedBg: Color(0xFFFFFFFF),
  );

  factory BrandColors.dark() => const BrandColors(
    success: Color(0xFF66BB6A),
    warning: Color(0xFFFFD54F),
    info: Color(0xFF4FC3F7),
    danger: Color(0xFFEF5350),
    elevatedBg: Color(0xFF1E1E1E),
  );

  @override
  BrandColors copyWith({
    Color? success,
    Color? warning,
    Color? info,
    Color? danger,
    Color? elevatedBg,
  }) => BrandColors(
    success: success ?? this.success,
    warning: warning ?? this.warning,
    info: info ?? this.info,
    danger: danger ?? this.danger,
    elevatedBg: elevatedBg ?? this.elevatedBg,
  );

  @override
  BrandColors lerp(ThemeExtension<BrandColors>? other, double t) {
    if (other is! BrandColors) return this;
    return BrandColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      info: Color.lerp(info, other.info, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      elevatedBg: Color.lerp(elevatedBg, other.elevatedBg, t)!,
    );
  }
}

/// Radii, spacing, elevations — keep the app’s “shape & rhythm” consistent.
@immutable
class BrandMetrics extends ThemeExtension<BrandMetrics> {
  final double radiusSm;
  final double radiusMd;
  final double radiusLg;

  /// Base spacing unit (use multiples of 4 or 8)
  final double spaceUnit;

  const BrandMetrics({
    required this.radiusSm,
    required this.radiusMd,
    required this.radiusLg,
    required this.spaceUnit,
  });

  factory BrandMetrics.standard() =>
      const BrandMetrics(radiusSm: 8, radiusMd: 12, radiusLg: 16, spaceUnit: 8);

  EdgeInsets gapXY(double x, double y) =>
      EdgeInsets.symmetric(horizontal: x * spaceUnit, vertical: y * spaceUnit);
  EdgeInsets gapAll(double n) => EdgeInsets.all(n * spaceUnit);
  SizedBox vh(double n) => SizedBox(height: n * spaceUnit);
  SizedBox vw(double n) => SizedBox(width: n * spaceUnit);

  @override
  BrandMetrics copyWith({
    double? radiusSm,
    double? radiusMd,
    double? radiusLg,
    double? spaceUnit,
  }) => BrandMetrics(
    radiusSm: radiusSm ?? this.radiusSm,
    radiusMd: radiusMd ?? this.radiusMd,
    radiusLg: radiusLg ?? this.radiusLg,
    spaceUnit: spaceUnit ?? this.spaceUnit,
  );

  @override
  BrandMetrics lerp(ThemeExtension<BrandMetrics>? other, double t) {
    if (other is! BrandMetrics) return this;
    return BrandMetrics(
      radiusSm: lerpDouble(radiusSm, other.radiusSm, t),
      radiusMd: lerpDouble(radiusMd, other.radiusMd, t),
      radiusLg: lerpDouble(radiusLg, other.radiusLg, t),
      spaceUnit: lerpDouble(spaceUnit, other.spaceUnit, t),
    );
  }
}

double lerpDouble(double a, double b, double t) => a + (b - a) * t;
