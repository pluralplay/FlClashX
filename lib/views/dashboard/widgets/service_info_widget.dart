import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flclashx/common/common.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

class ServiceInfoWidget extends ConsumerWidget {
  const ServiceInfoWidget({super.key});

  String? _decodeBase64IfNeeded(String? value) {
    if (value == null || value.isEmpty) return value;

    try {
      final decoded = utf8.decode(base64.decode(value));
      return decoded;
    } catch (e) {
      return value;
    }
  }

  Widget _buildLogo(BuildContext context, String? logoUrl) {
    const logoSize = 44.0;
    const borderRadius = 8.0;

    if (logoUrl == null || logoUrl.isEmpty) {
      return Icon(
        Icons.contact_mail,
        size: logoSize,
        color: context.colorScheme.primary,
      );
    }

    final isSvg = logoUrl.toLowerCase().endsWith('.svg');

    Widget logoWidget;
    if (isSvg) {
      logoWidget = SvgPicture.network(
        logoUrl,
        width: logoSize,
        height: logoSize,
        placeholderBuilder: (context) => Icon(
          Icons.contact_mail,
          size: logoSize,
          color: context.colorScheme.primary,
        ),
      );
    } else {
      logoWidget = CachedNetworkImage(
        imageUrl: logoUrl,
        width: logoSize,
        height: logoSize,
        fit: BoxFit.cover,
        placeholder: (context, url) => Icon(
          Icons.contact_mail,
          size: logoSize,
          color: context.colorScheme.primary,
        ),
        errorWidget: (context, url, error) => Icon(
          Icons.contact_mail,
          size: logoSize,
          color: context.colorScheme.primary,
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: logoWidget,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider);

    if (profile == null) {
      return const SizedBox.shrink();
    }

    final headers = profile.providerHeaders;
    final serviceName = _decodeBase64IfNeeded(headers['flclashx-servicename']);
    final supportUrl = headers['support-url'];
    final logoUrl = _decodeBase64IfNeeded(headers['flclashx-servicelogo']);

    if (serviceName == null || serviceName.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: getWidgetHeight(1),
      child: CommonCard(
        onPressed: (supportUrl != null && supportUrl.isNotEmpty)
            ? () {
                globalState.openUrl(supportUrl);
              }
            : null,
        child: Container(
          padding: baseInfoEdgeInsets.copyWith(
            top: 8,
            bottom: 8,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildLogo(context, logoUrl),
                    const SizedBox(width: 10),
                    Flexible(
                      child: EmojiText(
                        serviceName,
                        style: context.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w400,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              if (supportUrl != null && supportUrl.isNotEmpty) ...[
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: context.colorScheme.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.support_agent,
                    size: 28,
                    color: context.colorScheme.onPrimary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
