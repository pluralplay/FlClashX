import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:zxing2/qrcode.dart';

// Декодирование QR на Windows и Linux не зависит от mobile_scanner:
// для этих платформ у него нет реализации analyzeImage.
Future<String?> decodeQrImage(Uint8List bytes) async {
  if (bytes.isEmpty || bytes.lengthInBytes > 20 * 1024 * 1024) return null;

  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    const maxSide = 2048;
    final width = descriptor.width;
    final height = descriptor.height;
    codec = await descriptor.instantiateCodec(
      targetWidth: width >= height && width > maxSide ? maxSide : null,
      targetHeight: height > width && height > maxSide ? maxSide : null,
    );
    image = (await codec.getNextFrame()).image;
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (rgba == null) return null;

    final pixels = Int32List(image.width * image.height);
    for (var i = 0; i < pixels.length; i++) {
      final offset = i * 4;
      // Прозрачные пиксели накладываем на белый фон, иначе PNG без
      // подложки превращается в чёрный прямоугольник.
      final alpha = rgba.getUint8(offset + 3);
      final white = 255 * (255 - alpha);
      final red = (rgba.getUint8(offset) * alpha + white) ~/ 255;
      final green = (rgba.getUint8(offset + 1) * alpha + white) ~/ 255;
      final blue = (rgba.getUint8(offset + 2) * alpha + white) ~/ 255;
      pixels[i] = (red << 16) | (green << 8) | blue;
    }

    final source = RGBLuminanceSource(image.width, image.height, pixels);
    return QRCodeReader().decode(BinaryBitmap(HybridBinarizer(source))).text;
  } on Exception {
    // Файл может быть повреждён или не содержать QR.
    // Не записываем его содержимое (ссылку подписки) в лог.
    return null;
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}
