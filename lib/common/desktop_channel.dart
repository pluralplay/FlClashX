import 'dart:io';

import 'package:path/path.dart' as p;

/// The name setup.dart gives a Windows or Linux pre-release's executable.
const preExecutableName = 'FlClashXPre';

bool isPreExecutable(String executable) {
  final context = executable.contains(r'\') ? p.windows : p.posix;
  return context.basenameWithoutExtension(executable) == preExecutableName;
}

final bool isPreDesktopApp =
    (Platform.isWindows || Platform.isLinux) &&
    isPreExecutable(Platform.resolvedExecutable);

String helperServiceFor({required bool pre}) =>
    pre ? 'FlClashXPreHelperService' : 'FlClashXHelperService';

String helperPortKeyFor(String service) =>
    'SYSTEM\\CurrentControlSet\\Services\\$service\\Runtime';

String helperSocketPathFor({required bool pre}) =>
    '/run/${pre ? 'flclashx-pre' : 'flclashx'}/helper.sock';

String helperUnitPathFor({required bool pre}) =>
    '/etc/systemd/system/${pre ? 'flclashx-pre-helper' : 'flclashx-helper'}.service';
