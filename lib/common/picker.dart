import 'dart:io';
import 'dart:typed_data';

import 'qr_image.dart';

import 'package:file_picker/file_picker.dart';
import 'package:fl_clash/common/common.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class Picker {
  Future<PlatformFile?> pickerFile() async {
    return FilePicker.pickFile(initialDirectory: await appPath.downloadDirPath);
  }

  Future<Uri?> saveFile(String fileName, Uint8List bytes) async {
    final uri = await FilePicker.saveFile(
      fileName: fileName,
      initialDirectory: await appPath.downloadDirPath,
      bytes: bytes,
    );
    if (!system.isAndroid && uri != null && uri.scheme == 'file') {
      final file = File(uri.toFilePath());
      await file.safeWriteAsBytes(bytes);
    }
    return uri;
  }

  Future<Uri?> saveFileWithPath(String fileName, String localPath) async {
    final localFile = File(localPath);
    if (!await localFile.exists()) {
      await localFile.create(recursive: true);
    }
    final bytes = await localFile.readAsBytes();
    final uri = await FilePicker.saveFile(
      fileName: fileName,
      initialDirectory: await appPath.downloadDirPath,
      bytes: bytes,
    );
    await localFile.safeDelete();
    return uri;
  }

  Future<String?> pickerConfigQRCode() async {
    final Iterable<String?> values;
    if (system.isWindows || system.isLinux) {
      final file = await pickerFile();
      if (file == null) return null;
      values = [await decodeQrImage(await file.readAsBytes())];
    } else {
      final xFile = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (xFile == null) return null;
      // Не создаём временный контроллер: его dispose сбрасывает scan window
      // на странице сканирования, которая может оставаться открытой.
      final capture = await MobileScannerPlatform.instance.analyzeImage(
        xFile.path,
        formats: const [BarcodeFormat.qrCode],
      );
      values = capture?.barcodes.map((barcode) => barcode.rawValue) ?? const [];
    }
    final url = profileUrlFromQrCodes(values);
    if (url == null) {
      throw MessageException(currentAppLocalizations.pleaseUploadValidQrcode);
    }
    return url;
  }
}

extension PlatformFileExt on PlatformFile {
  Future<Uint8List> readBytes() {
    return readAsBytes();
  }
}

final picker = Picker();
