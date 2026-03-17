import 'package:cached_network_image/cached_network_image.dart';
import 'package:flclashx/common/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_svg/svg.dart';

class CommonTargetIcon extends StatelessWidget {
  const CommonTargetIcon({
    super.key,
    required this.src,
    required this.size,
  });
  final String src;
  final double size;

  Widget _defaultIcon() => Icon(
        IconsExt.target,
        size: size,
      );

  Widget _buildIcon() {
    if (src.isEmpty) {
      return _defaultIcon();
    }

    final base64 = src.getBase64;
    if (base64 != null) {
      return Image.memory(
        base64,
        gaplessPlayback: true,
        cacheWidth: (size * 2).toInt(),
        cacheHeight: (size * 2).toInt(),
        errorBuilder: (_, error, ___) => _defaultIcon(),
      );
    }

    if (src.isSvg) {
      return FutureBuilder(
        future: DefaultCacheManager().getSingleFile(src),
        builder: (_, snapshot) {
          final data = snapshot.data;
          if (data == null) {
            return const SizedBox();
          }
          return SvgPicture.file(
            data,
            width: size,
            height: size,
            errorBuilder: (_, __, ___) => _defaultIcon(),
          );
        },
      );
    }

    return CachedNetworkImage(
      imageUrl: src,
      width: size,
      height: size,
      fit: BoxFit.contain,
      memCacheWidth: (size * 2).toInt(),
      memCacheHeight: (size * 2).toInt(),
      placeholder: (_, __) => const SizedBox(),
      errorWidget: (_, __, ___) => _defaultIcon(),
    );
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: _buildIcon(),
      );
}
