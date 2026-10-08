import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../config/app_config.dart';

class UserAvatar extends StatelessWidget {
  final String? avatarUrl;
  final double radius;
  final Color? backgroundColor;
  final Widget? fallbackChild;

  const UserAvatar({
    super.key,
    required this.avatarUrl,
    this.radius = 24.0,
    this.backgroundColor,
    this.fallbackChild,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = backgroundColor ?? const Color(0xFF334155);
    final size = radius * 2;

    if (avatarUrl == null || avatarUrl!.trim().isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: bgColor,
        child: fallbackChild ?? Icon(Icons.person, color: Colors.white, size: radius * 1.1),
      );
    }

    String fullUrl = avatarUrl!.trim();
    if (!fullUrl.startsWith('http')) {
      if (!fullUrl.startsWith('/')) fullUrl = '/$fullUrl';
      fullUrl = '${AppConfig.apiBaseUrl.replaceAll('/api', '')}$fullUrl';
    }

    final isSvg = fullUrl.toLowerCase().contains('.svg');

    return ClipOval(
      child: Container(
        width: size,
        height: size,
        color: bgColor,
        child: isSvg
            ? SvgPicture.network(
                fullUrl,
                width: size,
                height: size,
                fit: BoxFit.cover,
                placeholderBuilder: (_) => Center(
                  child: fallbackChild ?? Icon(Icons.person, color: Colors.white, size: radius * 1.1),
                ),
              )
            : Image.network(
                fullUrl,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Center(
                  child: fallbackChild ?? Icon(Icons.person, color: Colors.white, size: radius * 1.1),
                ),
              ),
      ),
    );
  }
}
