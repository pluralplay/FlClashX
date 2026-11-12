import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'transform.dart';

/// What the profile build hands the chains: the whole config, script run.
final proxyChainGraphProvider = FutureProvider.autoDispose
    .family<ProxyChainGraph?, int>((ref, profileId) async {
      final source = ref.watch(
        profileProvider(profileId).select(
          (profile) => (
            type: profile?.type,
            extendType: profile?.extendType,
            scriptId: profile?.scriptId,
            updated: profile?.lastUpdateDate,
          ),
        ),
      );
      if (source.type == null || source.type == ProfileType.custom) {
        return null;
      }
      var raw = await ref.read(coreHandlerProvider).getConfig(profileId);
      final scriptId = source.scriptId;
      if (source.extendType == ExtendType.script && scriptId != null) {
        final script = await database.scriptsDao
            .get(scriptId)
            .getSingleOrNull();
        final content = await script?.content;
        if (content != null && content.isNotEmpty) {
          raw = await handleEvaluate(content, raw);
        }
      }
      return compute(ProxyChainGraph.fromRaw, raw);
    });
