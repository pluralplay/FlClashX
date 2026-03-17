import 'package:flclashx/common/common.dart';
import 'package:flutter/material.dart';

class CommonTheme {

  CommonTheme.of(
    this.context,
    this.textScaleFactor,
  ) : _colorMap = {};
  final BuildContext context;
  final Map<String, Color> _colorMap;
  final double textScaleFactor;

  Color get darkenSecondaryContainer => _colorMap.updateCacheValue(
        "darkenSecondaryContainer",
        () => context.colorScheme.secondaryContainer
            .blendDarken(context, factor: 0.1),
      )!;

  Color get darkenSecondaryContainerLighter => _colorMap.updateCacheValue(
        "darkenSecondaryContainerLighter",
        () => context.colorScheme.secondaryContainer
            .blendDarken(context, factor: 0.1)
            .opacity60,
      )!;

  Color get darken2SecondaryContainer => _colorMap.updateCacheValue(
        "darken2SecondaryContainer",
        () => context.colorScheme.secondaryContainer
            .blendDarken(context, factor: 0.2),
      )!;

  Color get darken3PrimaryContainer => _colorMap.updateCacheValue(
        "darken3PrimaryContainer",
        () => context.colorScheme.primaryContainer
            .blendDarken(context, factor: 0.3),
      )!;
}
