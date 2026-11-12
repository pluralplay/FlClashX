import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:zxing2/qrcode.dart';

const _maxSide = 2048;
const _maxBytes = 20 << 20;

typedef RgbaImage = ({Uint8List rgba, int width, int height});

/// For Windows and Linux, which mobile_scanner has no implementation for.
Future<List<String>> qrCodesInImageFile(String path) async {
  if (await File(path).length() > _maxBytes) {
    return const [];
  }
  final image = await _decodeRgba(path);
  return compute(qrCodesInRgba, image);
}

Future<RgbaImage> _decodeRgba(String path) async {
  final buffer = await ui.ImmutableBuffer.fromFilePath(path);
  final ui.ImageDescriptor descriptor;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
  } finally {
    buffer.dispose();
  }
  ui.Codec? codec;
  ui.Image? image;
  try {
    final scale = _maxSide / max(descriptor.width, descriptor.height);
    codec = await descriptor.instantiateCodec(
      targetWidth: scale < 1 ? (descriptor.width * scale).round() : null,
      targetHeight: scale < 1 ? (descriptor.height * scale).round() : null,
    );
    image = (await codec.getNextFrame()).image;
    final data = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    return (
      rgba: data!.buffer.asUint8List(),
      width: image.width,
      height: image.height,
    );
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor.dispose();
  }
}

@visibleForTesting
List<String> qrCodesInRgba(RgbaImage image) {
  final pixels = Int32List(image.width * image.height);
  final rgba = image.rgba;
  for (var i = 0; i < pixels.length; i++) {
    final o = i * 4;
    // A code saved on a transparent background reads as black on black
    // unless it is laid over white.
    final alpha = rgba[o + 3];
    final white = 255 * (255 - alpha);
    int channel(int value) => (value * alpha + white) ~/ 255;
    pixels[i] =
        0xFF000000 |
        channel(rgba[o]) << 16 |
        channel(rgba[o + 1]) << 8 |
        channel(rgba[o + 2]);
  }
  final source = RGBLuminanceSource(image.width, image.height, pixels);
  final hints = DecodeHints()..put(DecodeHintType.tryHarder);
  for (final luminance in [source, InvertedLuminanceSource(source)]) {
    try {
      final result = QRCodeReader().decode(
        BinaryBitmap(HybridBinarizer(luminance)),
        hints: hints,
      );
      return [result.text];
    } on ReaderException {
      continue;
    }
  }
  return const [];
}
