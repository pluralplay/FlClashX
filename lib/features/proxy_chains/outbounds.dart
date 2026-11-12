import 'package:fl_clash/common/common.dart';
import 'package:collection/collection.dart';
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
      final scriptId = source.extendType == ExtendType.script
          ? source.scriptId
          : null;
      // A save or download bumps the script's update time, so the graph
      // follows edits to the script the profile runs.
      final script = scriptId == null
          ? null
          : ref.watch(
              scriptsProvider.select(
                (state) => state.value?.firstWhereOrNull(
                  (item) => item.id == scriptId,
                ),
              ),
            );
      var raw = await ref.read(coreHandlerProvider).getConfig(profileId);
      final content = await script?.content;
      if (content != null && content.isNotEmpty) {
        raw = await handleEvaluate(content, raw);
      }
      return compute(ProxyChainGraph.fromRaw, raw);
    });
