import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flclashx/clash/message.dart';
import 'package:flclashx/common/common.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';

mixin ClashInterface {
  Future<bool> init(InitParams params);

  Future<bool> preload();

  Future<bool> shutdown();

  Future<bool> get isInit;

  Future<bool> forceGc();

  FutureOr<String> validateConfig(String data);

  FutureOr<Result> getConfig(String path);

  Future<String> asyncTestDelay(String url, String proxyName);

  FutureOr<String> updateConfig(UpdateParams updateParams);

  FutureOr<String> setupConfig(SetupParams setupParams);

  FutureOr<Map> getProxies();

  FutureOr<String> changeProxy(ChangeProxyParams changeProxyParams);

  Future<bool> startListener();

  Future<bool> stopListener();

  FutureOr<String> getExternalProviders();

  FutureOr<String>? getExternalProvider(String externalProviderName);

  Future<String> updateGeoData(UpdateGeoDataParams params);

  Future<String> sideLoadExternalProvider({
    required String providerName,
    required String data,
  });

  Future<String> updateExternalProvider(String providerName);

  FutureOr<String> getTraffic();

  FutureOr<String> getTotalTraffic();

  FutureOr<String> getCountryCode(String ip);

  FutureOr<String> getMemory();

  resetTraffic();

  startLog();

  stopLog();

  Future<bool> crash();

  FutureOr<String> getConnections();

  FutureOr<bool> closeConnection(String id);

  FutureOr<bool> closeConnections();

  FutureOr<bool> resetConnections();

  Future<bool> setState(CoreState state);
}

mixin AndroidClashInterface {
  Future<bool> updateDns(String value);

  Future<AndroidVpnOptions?> getAndroidVpnOptions();

  Future<String> getCurrentProfileName();

  Future<DateTime?> getRunTime();
}

abstract class ClashHandlerInterface with ClashInterface {
  Map<String, Completer> callbackCompleterMap = {};

  Future<void> handleResult(ActionResult result) async {
    final completer = callbackCompleterMap[result.id];
    try {
      switch (result.method) {
        case ActionMethod.message:
          clashMessage.controller.add(result.data);
          completer?.complete(true);
          return;
        case ActionMethod.getConfig:
          completer?.complete(result.toResult);
          return;
        default:
          completer?.complete(result.data);
          return;
      }
    } catch (e) {
      commonPrint.log("${result.id} error $e");
    }
  }

  sendMessage(String message);

  reStart();

  FutureOr<bool> destroy();

  Future<T> invoke<T>({
    required ActionMethod method,
    dynamic data,
    Duration? timeout,
    FutureOr<T> Function()? onTimeout,
    T? defaultValue,
  }) async {
    final id = "${method.name}#${utils.id}";

    callbackCompleterMap[id] = Completer<T>();

    dynamic mDefaultValue = defaultValue;
    if (mDefaultValue == null) {
      if (T == String) {
        mDefaultValue = "";
      } else if (T == bool) {
        mDefaultValue = false;
      } else if (T == Map) {
        mDefaultValue = {};
      }
    }

    sendMessage(
      json.encode(
        Action(
          id: id,
          method: method,
          data: data,
        ),
      ),
    );

    return (callbackCompleterMap[id]! as Completer<T>).safeFuture(
      timeout: timeout,
      onLast: () {
        callbackCompleterMap.remove(id);
      },
      onTimeout: onTimeout ??
          () => mDefaultValue as T,
      functionName: id,
    ) as Future<T>;
  }

  @override
  Future<bool> init(InitParams params) => invoke<bool>(
      method: ActionMethod.initClash,
      data: json.encode(params),
    );

  @override
  Future<bool> setState(CoreState state) => invoke<bool>(
      method: ActionMethod.setState,
      data: json.encode(state),
    );

  @override
  @override
  Future<bool> shutdown() => invoke<bool>(
      method: ActionMethod.shutdown,
      timeout: const Duration(seconds: 1),
    );

  @override
  Future<bool> get isInit => invoke<bool>(
        method: ActionMethod.getIsInit,
      );

  @override
  Future<bool> forceGc() => invoke<bool>(
        method: ActionMethod.forceGc,
      );

  @override
  FutureOr<String> validateConfig(String data) => invoke<String>(
        method: ActionMethod.validateConfig,
        data: data,
      );

  @override
  Future<String> updateConfig(UpdateParams updateParams) => invoke<String>(
        method: ActionMethod.updateConfig,
        data: json.encode(updateParams),
        timeout: const Duration(minutes: 2),
      );

  @override
  Future<Result> getConfig(String path) => invoke<Result>(
        method: ActionMethod.getConfig,
        data: path,
        timeout: const Duration(minutes: 2),
        defaultValue: Result.success({}),
      );

  @override
  Future<String> setupConfig(SetupParams setupParams) async {
    final data = await Isolate.run(() => json.encode(setupParams));
    return invoke<String>(
      method: ActionMethod.setupConfig,
      data: data,
      timeout: const Duration(minutes: 2),
    );
  }

  @override
  Future<bool> crash() => invoke<bool>(
      method: ActionMethod.crash,
    );

  @override
  Future<Map> getProxies() => invoke<Map>(
      method: ActionMethod.getProxies,
      timeout: const Duration(seconds: 5),
    );

  @override
  FutureOr<String> changeProxy(ChangeProxyParams changeProxyParams) => invoke<String>(
      method: ActionMethod.changeProxy,
      data: json.encode(changeProxyParams),
    );

  @override
  FutureOr<String> getExternalProviders() => invoke<String>(
      method: ActionMethod.getExternalProviders,
    );

  @override
  FutureOr<String> getExternalProvider(String externalProviderName) => invoke<String>(
      method: ActionMethod.getExternalProvider,
      data: externalProviderName,
    );

  @override
  Future<String> updateGeoData(UpdateGeoDataParams params) => invoke<String>(
        method: ActionMethod.updateGeoData,
        data: json.encode(params),
        timeout: const Duration(minutes: 1));

  @override
  Future<String> sideLoadExternalProvider({
    required String providerName,
    required String data,
  }) => invoke<String>(
      method: ActionMethod.sideLoadExternalProvider,
      data: json.encode({
        "providerName": providerName,
        "data": data,
      }),
    );

  @override
  Future<String> updateExternalProvider(String providerName) => invoke<String>(
      method: ActionMethod.updateExternalProvider,
      data: providerName,
      timeout: const Duration(minutes: 1),
    );

  @override
  FutureOr<String> getConnections() => invoke<String>(
      method: ActionMethod.getConnections,
    );

  @override
  Future<bool> closeConnections() => invoke<bool>(
      method: ActionMethod.closeConnections,
    );

  @override
  Future<bool> resetConnections() => invoke<bool>(
      method: ActionMethod.resetConnections,
    );

  @override
  Future<bool> closeConnection(String id) => invoke<bool>(
      method: ActionMethod.closeConnection,
      data: id,
    );

  @override
  FutureOr<String> getTotalTraffic() => invoke<String>(
      method: ActionMethod.getTotalTraffic,
    );

  @override
  FutureOr<String> getTraffic() => invoke<String>(
      method: ActionMethod.getTraffic,
    );

  @override
  void resetTraffic() {
    invoke(method: ActionMethod.resetTraffic);
  }

  @override
  void startLog() {
    invoke(method: ActionMethod.startLog);
  }

  @override
  void stopLog() {
    invoke<bool>(
      method: ActionMethod.stopLog,
    );
  }

  @override
  Future<bool> startListener() => invoke<bool>(
      method: ActionMethod.startListener,
    );

  @override
  Future<bool> stopListener() => invoke<bool>(
      method: ActionMethod.stopListener,
    );

  @override
  Future<String> asyncTestDelay(String url, String proxyName) {
    final delayParams = {
      "proxy-name": proxyName,
      "timeout": httpTimeoutDuration.inMilliseconds,
      "test-url": url,
    };
    return invoke<String>(
      method: ActionMethod.asyncTestDelay,
      data: json.encode(delayParams),
      timeout: const Duration(
        milliseconds: 6000,
      ),
      onTimeout: () => json.encode(
          Delay(
            name: proxyName,
            value: -1,
            url: url,
          ),
        ),
    );
  }

  @override
  FutureOr<String> getCountryCode(String ip) => invoke<String>(
      method: ActionMethod.getCountryCode,
      data: ip,
    );

  @override
  FutureOr<String> getMemory() => invoke<String>(
      method: ActionMethod.getMemory,
    );
}
