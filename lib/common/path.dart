import 'dart:async';
import 'dart:io';

import 'package:flclashx/common/common.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class AppPath {

  factory AppPath() {
    _instance ??= AppPath._internal();
    return _instance!;
  }

  AppPath._internal() {
    appDirPath = join(dirname(Platform.resolvedExecutable));
    getApplicationSupportDirectory().then((value) {
      dataDir.complete(value);
    });
    getTemporaryDirectory().then((value) {
      tempDir.complete(value);
    });
    getDownloadsDirectory().then((value) {
      downloadDir.complete(value);
    });
  }
  static AppPath? _instance;
  Completer<Directory> dataDir = Completer();
  Completer<Directory> downloadDir = Completer();
  Completer<Directory> tempDir = Completer();
  late String appDirPath;

  String get executableExtension => Platform.isWindows ? ".exe" : "";

  String get executableDirPath {
    final currentExecutablePath = Platform.resolvedExecutable;
    return dirname(currentExecutablePath);
  }

  String get corePath {
    if (Platform.isMacOS) {
      // Core is stored in Application Support/com.follow.clash/cores/ (copied by Swift code on launch)
      // Permissions are set automatically in Swift
      final home = Platform.environment['HOME'] ?? '';
      return '$home/Library/Application Support/com.follow.clash/cores/FlClashCore';
    }
    return join(executableDirPath, "FlClashCore$executableExtension");
  }

  String get helperPath => join(executableDirPath, "$appHelperService$executableExtension");

  Future<String> get downloadDirPath async {
    final directory = await downloadDir.future;
    return directory.path;
  }

  Future<String> get homeDirPath async {
    final directory = await dataDir.future;
    return directory.path;
  }

  Future<String> get lockFilePath async {
    final directory = await dataDir.future;
    return join(directory.path, "FlClashX.lock");
  }

  Future<String> get sharedPreferencesPath async {
    final directory = await dataDir.future;
    return join(directory.path, "shared_preferences.json");
  }

  Future<String> get profilesPath async {
    final directory = await dataDir.future;
    return join(directory.path, profilesDirectoryName);
  }

  Future<String> getProfilePath(String id) async {
    final directory = await profilesPath;
    return join(directory, "$id.yaml");
  }

  Future<String> getProvidersDirPath(String id) async {
    final directory = await profilesPath;
    return join(
      directory,
      "providers",
      id,
    );
  }

  Future<String> getProvidersFilePath(
    String id,
    String type,
    String url,
  ) async {
    final directory = await profilesPath;
    return join(
      directory,
      "providers",
      id,
      type,
      url.toMd5(),
    );
  }

  Future<String> get tempPath async {
    final directory = await tempDir.future;
    return directory.path;
  }
}

final appPath = AppPath();
