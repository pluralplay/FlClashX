import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'clash_config.dart';
import 'provider_headers.dart';

part 'generated/profile.freezed.dart';
part 'generated/profile.g.dart';

typedef ValidateConfig =
    Future<String> Function(String path, String ageSecretKey);

@freezed
abstract class SubscriptionInfo with _$SubscriptionInfo {
  const factory SubscriptionInfo({
    @Default(0) int upload,
    @Default(0) int download,
    @Default(0) int total,
    @Default(0) int expire,
  }) = _SubscriptionInfo;

  factory SubscriptionInfo.fromJson(Map<String, Object?> json) =>
      _$SubscriptionInfoFromJson(json);

  factory SubscriptionInfo.formHString(String? info) {
    if (info == null) return const SubscriptionInfo();
    final Map<String, int> map = {};
    for (final field in info.split(';')) {
      final separator = field.indexOf('=');
      if (separator == -1) continue;
      final value = _parseCount(field.substring(separator + 1).trim());
      if (value != null) {
        map[field.substring(0, separator).trim().toLowerCase()] = value;
      }
    }
    return SubscriptionInfo(
      upload: map['upload'] ?? 0,
      download: map['download'] ?? 0,
      total: map['total'] ?? 0,
      expire: map['expire'] ?? 0,
    );
  }

  static int? _parseCount(String value) {
    final count = int.tryParse(value);
    if (count != null) return count;
    final decimal = double.tryParse(value);
    return decimal != null && decimal.isFinite ? decimal.truncate() : null;
  }
}

extension SubscriptionInfoExt on SubscriptionInfo {
  double? get usage =>
      total > 0 ? ((upload + download) / total).clamp(0.0, 1.0) : null;

  DateTime? get expireDate =>
      expire > 0 ? DateTime.fromMillisecondsSinceEpoch(expire * 1000) : null;
}

@freezed
abstract class Profile with _$Profile {
  const factory Profile({
    required int id,
    @Default(ProfileType.file) ProfileType type,
    @Default('') String label,
    String? currentGroupName,
    @Default('') String url,
    @Default('') String ageSecretKey,
    DateTime? lastUpdateDate,
    required Duration autoUpdateDuration,
    SubscriptionInfo? subscriptionInfo,
    @Default(true) bool autoUpdate,
    @Default({}) Map<String, String> selectedMap,
    @Default({}) Set<String> unfoldSet,
    @Default(ExtendType.standard) ExtendType extendType,
    int? scriptId,
    String? matchTarget,
    int? order,
    @Default(ProfileOverrides())
    @JsonKey(fromJson: ProfileOverrides.safeFromJson)
    ProfileOverrides overrides,

    /// The subscription's response headers, lower-cased, see [providerHeaderNames].
    @Default({}) Map<String, String> providerHeaders,

    /// Whether downloads carry the device id headers a panel binds by.
    @Default(true) bool sendDeviceHeaders,
  }) = _Profile;

  factory Profile.fromJson(Map<String, Object?> json) =>
      _$ProfileFromJson(json);

  factory Profile.normal({
    String? label,
    String url = '',
    bool sendDeviceHeaders = true,
  }) {
    final id = snowflake.id;
    return Profile(
      type: url.isEmpty ? ProfileType.file : ProfileType.url,
      label: label ?? '',
      url: url,
      id: id,
      autoUpdateDuration: defaultUpdateDuration,
      sendDeviceHeaders: sendDeviceHeaders,
    );
  }

  factory Profile.custom({String? label}) {
    return Profile(
      id: snowflake.id,
      type: ProfileType.custom,
      label: label ?? '',
      lastUpdateDate: DateTime.now(),
      autoUpdate: false,
      autoUpdateDuration: defaultUpdateDuration,
    );
  }
}

/// A profile leaving out one of the global rules its extension would add.
@freezed
abstract class DisabledRule with _$DisabledRule {
  const factory DisabledRule({required int profileId, required int ruleId}) =
      _DisabledRule;
}

extension ProfilesExt on List<Profile> {
  Profile? getProfile(int? profileId) {
    final index = indexWhere((profile) => profile.id == profileId);
    return index == -1 ? null : this[index];
  }

  Profile optimizeLabel(Profile profile) {
    return profile.copyWith(
      label: uniqueLabelFor(
        profile.label,
        fallback: profile.defaultLabel,
        taken: (label) =>
            any((item) => item.label == label && item.id != profile.id),
      ),
    );
  }
}

extension ProfileExtension on Profile {
  bool get realAutoUpdate => type == ProfileType.url && autoUpdate;

  String get realLabel => label.takeFirstValid([defaultLabel]);

  String get defaultLabel => url.webUri?.host ?? id.toString();

  String get fileName => '$id.yaml';

  String get exportFileName {
    final label = realLabel;
    final lower = label.toLowerCase();
    if (lower.endsWith('.yaml') || lower.endsWith('.yml')) {
      return label;
    }
    return '$label.yaml';
  }

  String get updatingKey => 'profile_$id';

  Future<Profile?> checkAndUpdateAndCopy({
    required ValidateConfig validate,
  }) async {
    if (type != ProfileType.url) {
      return null;
    }
    final mFile = await _getFile(false);
    if (await mFile.exists()) {
      return null;
    }
    return update(validate: validate);
  }

  Future<File> _getFile([bool autoCreate = true]) async {
    final path = await appPath.getProfilePath(id.toString());
    final file = File(path);
    final isExists = await file.exists();
    if (!isExists && autoCreate) {
      return file.create(recursive: true);
    }
    return file;
  }

  Future<File> get file async {
    return _getFile();
  }

  /// Downloads from [url], then from the panel's fallback hosts in order; a
  /// hard failure of [url] moves the profile onto the host that answered.
  Future<Profile> update({
    required ValidateConfig validate,
    SubscriptionFetch? fetch,
    DeviceHeaders? deviceHeaders,
  }) async {
    fetch ??= request.getFileResponseForUrl;
    final sent = sendDeviceHeaders
        ? await (deviceHeaders ?? deviceIdentity.headers)()
        : const <String, String>{};
    final Object firstError;
    final StackTrace firstTrace;
    try {
      return await _updateFrom(
        url,
        validate,
        fetch,
        sent,
        downloadTimeoutDuration,
      );
    } catch (error, trace) {
      firstError = error;
      firstTrace = trace;
    }
    final fallbacks = headers.fallbackUrlsOf(Uri.tryParse(url) ?? Uri());
    if (fallbacks.isEmpty) {
      Error.throwWithStackTrace(firstError, firstTrace);
    }
    final failure = hostFailureOf(firstError);
    commonPrint.log(
      'subscription host failed (${failure.name}): ${compactError(firstError)}',
      logLevel: LogLevel.warning,
    );
    for (final fallback in fallbacks) {
      try {
        final updated = await _updateFrom(
          fallback.toString(),
          validate,
          fetch,
          sent,
          fallbackTimeoutDuration,
        );
        commonPrint.log(
          'subscription served by ${fallback.host}'
          '${failure == HostFailure.hard ? ', profile moved there' : ''}',
        );
        return failure == HostFailure.hard
            ? updated.copyWith(url: fallback.toString())
            : updated;
      } catch (error) {
        commonPrint.log(
          'fallback ${fallback.host} failed: ${compactError(error)}',
          logLevel: LogLevel.warning,
        );
      }
    }
    Error.throwWithStackTrace(firstError, firstTrace);
  }

  Future<Profile> _updateFrom(
    String url,
    ValidateConfig validate,
    SubscriptionFetch fetch,
    Map<String, String> headers,
    Duration timeout,
  ) async {
    final response = await fetch(url, timeout: timeout, headers: headers);
    final disposition = response.headers.value('content-disposition');
    final userinfo = response.headers.value('subscription-userinfo');
    final providerHeaders = providerHeadersOf(response.headers.map);
    return copyWith(
      label: label.takeFirstValid([
        ProviderHeaders(providerHeaders).title,
        getFileNameForDisposition(disposition),
        defaultLabel,
      ]),
      subscriptionInfo: SubscriptionInfo.formHString(userinfo),
      providerHeaders: providerHeaders,
      autoUpdateDuration:
          ProviderHeaders(providerHeaders).updateInterval ?? autoUpdateDuration,
    ).saveFile(
      decompressUnlabeled(response.data ?? Uint8List(0)),
      validate: validate,
    );
  }

  Future<Profile> saveFile(
    Uint8List bytes, {
    required ValidateConfig validate,
  }) async {
    final path = await appPath.tempFilePath;
    final tempFile = File(path);
    await tempFile.safeWriteAsBytes(bytes);
    final message = await validate(path, ageSecretKey);
    if (message.isNotEmpty) {
      throw MessageException(message);
    }
    final mFile = await file;
    await tempFile.copy(mFile.path);
    await tempFile.safeDelete();
    return copyWith(lastUpdateDate: DateTime.now());
  }
}

typedef SubscriptionFetch =
    Future<Response<Uint8List>> Function(
      String url, {
      Duration timeout,
      Map<String, String> headers,
    });

typedef DeviceHeaders = Future<Map<String, String>> Function();

const fallbackTimeoutDuration = Duration(seconds: 10);

const providerHeaderNames = {
  'announce',
  'support-url',
  'profile-title',
  'profile-web-page-url',
  'profile-update-interval',
  'x-hwid-max-devices-reached',
  'x-hwid-not-supported',
};

const providerHeaderPrefix = 'flclashx-';

/// The subscription's own headers, keys lower-cased, first value kept.
Map<String, String> providerHeadersOf(Map<String, List<String>> headers) {
  return {
    for (final MapEntry(:key, :value) in headers.entries)
      if (value.isNotEmpty)
        if (providerHeaderNames.contains(key.toLowerCase()) ||
            key.toLowerCase().startsWith(providerHeaderPrefix))
          key.toLowerCase(): value.first,
  };
}
