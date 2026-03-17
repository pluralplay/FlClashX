import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flclashx/common/common.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/state.dart';
import 'package:flutter/cupertino.dart';

class Request {

  Request() {
    _dio = Dio(
      BaseOptions(
        headers: {
          "User-Agent": browserUa,
        },
      ),
    );
    _clashDio = Dio();
    _clashDio.httpClientAdapter = IOHttpClientAdapter(createHttpClient: () {
      final client = HttpClient();
      client.findProxy = (uri) {
        client.userAgent = globalState.ua;
        return FlClashHttpOverrides.handleFindProxy(uri);
      };
      return client;
    });
  }
  late final Dio _dio;
  late final Dio _clashDio;
  String? userAgent;

  Future<Response<Uint8List>> getFileResponseForUrl(
    String url, {
    Map<String, dynamic>? headers,
  }) async {
    final requestHeaders = headers ?? {};
    requestHeaders['User-Agent'] = globalState.ua;

    final firstResponse = await _dio.get<Uint8List>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        headers: requestHeaders,
        followRedirects: false,
        validateStatus: (status) => status != null && status < 400,
      ),
    );

    if (firstResponse.isRedirect == true) {
      final newUrl = firstResponse.headers.value('location');
      if (newUrl == null) {
        throw Exception('Redirect detected, but no location header was found.');
      }

      print('↪️ Redirecting to: $newUrl');
      final finalResponse = await _dio.get<Uint8List>(
        newUrl,
        options: Options(
          responseType: ResponseType.bytes,
          headers: requestHeaders,
          followRedirects: true,
          maxRedirects: 5,
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      return finalResponse;
    }
    return firstResponse;
  }

  Future<Response> getTextResponseForUrl(String url) async {
    final response = await _clashDio.get(
      url,
      options: Options(
        responseType: ResponseType.plain,
      ),
    );
    return response;
  }

  Future<MemoryImage?> getImage(String url) async {
    if (url.isEmpty) return null;
    final response = await _dio.get<Uint8List>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
      ),
    );
    final data = response.data;
    if (data == null) return null;
    return MemoryImage(data);
  }

  Future<Map<String, dynamic>?> checkForUpdate() async {
    final response = await _dio.get(
      "https://api.github.com/repos/$repository/releases/latest",
      options: Options(
        responseType: ResponseType.json,
      ),
    );
    if (response.statusCode != 200) return null;
    final data = response.data as Map<String, dynamic>;
    final remoteVersion = data['tag_name'];
    final version = globalState.packageInfo.version;
    final hasUpdate =
        utils.compareVersions(remoteVersion.replaceAll('v', ''), version) > 0;
    if (!hasUpdate) return null;
    return data;
  }

  final Map<String, IpInfo Function(Map<String, dynamic>)> _ipInfoSources = {
    "https://ipwho.is/": IpInfo.fromIpwhoIsJson,
    "https://api.ip.sb/geoip/": IpInfo.fromIpSbJson,
    "https://ipapi.co/json/": IpInfo.fromIpApiCoJson,
    "https://ipinfo.io/json/": IpInfo.fromIpInfoIoJson,
  };

  Future<Result<IpInfo?>> checkIp({CancelToken? cancelToken}) async {
    var failureCount = 0;
    final futures = _ipInfoSources.entries.map((source) async {
      final completer = Completer<Result<IpInfo?>>();
      final future = Dio().get<Map<String, dynamic>>(
        source.key,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.json,
        ),
      );
      future.then((res) {
        if (res.statusCode == HttpStatus.ok && res.data != null) {
          completer.complete(Result.success(source.value(res.data!)));
        } else {
          failureCount++;
          if (failureCount == _ipInfoSources.length) {
            completer.complete(Result.success(null));
          }
        }
      }).catchError((e) {
        failureCount++;
        if (e == DioExceptionType.cancel) {
          completer.complete(Result.error("cancelled"));
        }
      });
      return completer.future;
    });
    final res = await Future.any(futures);
    cancelToken?.cancel();
    return res;
  }

  Future<bool> pingHelper() async {
    try {
      final response = await _dio
          .get(
            "http://$localhost:$helperPort/ping",
            options: Options(
              responseType: ResponseType.plain,
            ),
          )
          .timeout(
            const Duration(
              milliseconds: 2000,
            ),
          );
      if (response.statusCode != HttpStatus.ok) {
        return false;
      }
      return (response.data as String) == globalState.coreSHA256;
    } catch (_) {
      return false;
    }
  }

  Future<bool> startCoreByHelper(String arg) async {
    try {
      final homeDirPath = await appPath.homeDirPath;
      final response = await _dio
          .post(
            "http://$localhost:$helperPort/start",
            data: json.encode({
              "path": appPath.corePath,
              "arg": arg,
              "home_dir": homeDirPath,
            }),
            options: Options(
              responseType: ResponseType.plain,
            ),
          )
          .timeout(
            const Duration(
              milliseconds: 2000,
            ),
          );
      if (response.statusCode != HttpStatus.ok) {
        return false;
      }
      final data = response.data as String;
      return data.isEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> stopCoreByHelper() async {
    try {
      final response = await _dio
          .post(
            "http://$localhost:$helperPort/stop",
            options: Options(responseType: ResponseType.plain),
          )
          .timeout(const Duration(milliseconds: 2000));

      if (response.statusCode != HttpStatus.ok) return false;
      final data = response.data as String;
      return data.isEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> getCoreVersion() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        "http://$defaultExternalController/version",
        options: Options(
          responseType: ResponseType.json,
        ),
      ).timeout(const Duration(seconds: 2));
      
      if (response.statusCode != HttpStatus.ok) return null;
      return response.data;
    } catch (_) {
      return null;
    }
  }
}

final request = Request();
