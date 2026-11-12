import 'package:fl_clash/common/exception.dart';
import 'package:fl_clash/common/task.dart';
import 'package:flutter/foundation.dart';
import 'package:rust_api/rust_api.dart';

typedef ScriptEvaluator =
    Future<String> Function({required String script, required String config});

@visibleForTesting
ScriptEvaluator scriptEvaluator = evaluateScript;

Future<Map<String, dynamic>> handleEvaluate(
  String scriptContent,
  Map<String, dynamic> config,
) async {
  if (config['proxy-providers'] == null) {
    config['proxy-providers'] = {};
  }
  final encoded = await encodeJSONTask(config);
  final String result;
  try {
    result = await scriptEvaluator(script: scriptContent, config: encoded);
  } catch (e) {
    throw MessageException(e.toString());
  }
  final decoded = await decodeJSONTask<Object?>(result);
  if (decoded is! Map<String, dynamic>) {
    throw const MessageException(
      'script did not return a configuration object',
    );
  }
  return decoded;
}
