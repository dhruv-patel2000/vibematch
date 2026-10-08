import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../../core/config/app_config.dart';

class GiftImage extends StatelessWidget {
  final String? imageUrl;
  final String giftName;
  final double width;
  final double height;
  final double emojiSize;

  const GiftImage({
    super.key,
    required this.imageUrl,
    required this.giftName,
    this.width = 44.0,
    this.height = 44.0,
    this.emojiSize = 28.0,
  });

  static String getEmoji(String name) {
    final n = name.toLowerCase();
    if (n.contains('rose')) return '🌹';
    if (n.contains('diamond') || n.contains('ring')) return '💍';
    if (n.contains('gem') || n.contains('stone')) return '💎';
    if (n.contains('heart')) return '❤️';
    if (n.contains('crown')) return '👑';
    if (n.contains('car') || n.contains('super car')) return '🏎️';
    if (n.contains('rocket')) return '🚀';
    if (n.contains('fire')) return '🔥';
    if (n.contains('kiss')) return '💋';
    if (n.contains('bear') || n.contains('teddy')) return '🧸';
    if (n.contains('star')) return '⭐';
    if (n.contains('ribbon')) return '🎀';
    if (n.contains('trophy')) return '🏆';
    if (n.contains('popper') || n.contains('party')) return '🎉';
    if (n.contains('balloon')) return '🎈';
    if (n.contains('chocolate')) return '🍫';
    if (n.contains('lollipop')) return '🍭';
    if (n.contains('cocktail')) return '🍸';
    if (n.contains('beer')) return '🍺';
    if (n.contains('champagne')) return '🍾';
    if (n.contains('cake')) return '🎂';
    if (n.contains('money') || n.contains('bag')) return '💰';
    if (n.contains('credit') || n.contains('card')) return '💳';
    if (n.contains('wand')) return '🪄';
    if (n.contains('lipstick')) return '💄';
    if (n.contains('handshake')) return '🤝';
    if (n.contains('airplane') || n.contains('plane')) return '✈️';
    if (n.contains('helicopter')) return '🚁';
    if (n.contains('ship') || n.contains('cruise')) return '🚢';
    if (n.contains('box') || n.contains('gift')) return '🎁';
    return '🎁';
  }

  @override
  Widget build(BuildContext context) {
    final emoji = getEmoji(giftName);

    if (imageUrl == null || imageUrl!.trim().isEmpty) {
      return SizedBox(
        width: width,
        height: height,
        child: Center(
          child: Text(emoji, style: TextStyle(fontSize: emojiSize)),
        ),
      );
    }

    String fullUrl = imageUrl!.trim();
    if (!fullUrl.startsWith('http')) {
      if (!fullUrl.startsWith('/')) fullUrl = '/$fullUrl';
      fullUrl = '${AppConfig.apiBaseUrl.replaceAll('/api', '')}$fullUrl';
    }

    final isSvg = fullUrl.toLowerCase().contains('.svg');

    return SizedBox(
      width: width,
      height: height,
      child: Center(
        child: isSvg
            ? SvgPicture.network(
                fullUrl,
                width: width,
                height: height,
                fit: BoxFit.contain,
                placeholderBuilder: (_) => Text(emoji, style: TextStyle(fontSize: emojiSize)),
              )
            : Image.network(
                fullUrl,
                width: width,
                height: height,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Text(emoji, style: TextStyle(fontSize: emojiSize)),
              ),
      ),
    );
  }
}
