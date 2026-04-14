import 'dart:io';

import 'package:flclashx/common/common.dart';
import 'package:flclashx/state.dart';

class FlClashHttpOverrides extends HttpOverrides {
  static String handleFindProxy(Uri url) {
    if ([localhost].contains(url.host)) {
      return "DIRECT";
    }
    final port = globalState.config.patchClashConfig.mixedPort;
    final isStart = globalState.appState.runTime != null;
    commonPrint.log("find $url proxy:$isStart");
    if (!isStart) return "DIRECT";
    return "PROXY localhost:$port";
  }

  static Future<bool> handleAuthenticateProxy(
    HttpClient client,
    String host,
    int port,
    String scheme,
    String? realm,
  ) async {
    // Only authenticate if we're actually going through the proxy.
    final isStart = globalState.appState.runTime != null;
    if (!isStart) return false;
    final auth = globalState.config.patchClashConfig.authentication;
    if (auth.isEmpty) return false;
    final first = auth.first;
    final sep = first.indexOf(':');
    if (sep <= 0) return false;
    final user = first.substring(0, sep);
    final pass = first.substring(sep + 1);
    client.addProxyCredentials(
      host,
      port,
      realm ?? '',
      HttpClientBasicCredentials(user, pass),
    );
    return true;
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback = (_, __, ___) => true;
    client.findProxy = handleFindProxy;
    client.authenticateProxy =
        (host, port, scheme, realm) =>
            handleAuthenticateProxy(client, host, port, scheme, realm);
    return client;
  }
}
