import 'dart:io';

import 'package:flclashx/common/common.dart';

class SingleInstanceLock {

  factory SingleInstanceLock() {
    _instance ??= SingleInstanceLock._internal();
    return _instance!;
  }

  SingleInstanceLock._internal();
  static SingleInstanceLock? _instance;
  RandomAccessFile? _accessFile;

  Future<bool> acquire() async {
    try {
      final lockFilePath = await appPath.lockFilePath;
      final lockFile = File(lockFilePath);
      await lockFile.create();
      _accessFile = await lockFile.open(mode: FileMode.write);
      await _accessFile?.lock();
      return true;
    } catch (_) {
      return false;
    }
  }
}

final singleInstanceLock = SingleInstanceLock();
