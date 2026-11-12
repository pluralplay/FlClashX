const _base = 36;
const _tMin = 1;
const _tMax = 26;
const _skew = 38;
const _damp = 700;
const _initialBias = 72;
const _initialN = 128;
const _maxCodePoint = 0x10FFFF;
const _maxLabelLength = 63;

final _acePrefix = RegExp(r'(^|\.)xn--', caseSensitive: false);

/// [host] with each `xn--` label shown as the Unicode it encodes (RFC 3492);
/// a label that does not decode stays as it came.
String decodeIdnHost(String host) {
  if (!_acePrefix.hasMatch(host)) {
    return host;
  }
  return host.split('.').map(_decodeLabel).join('.');
}

String _decodeLabel(String label) {
  if (label.length <= 4 ||
      label.length > _maxLabelLength ||
      label.substring(0, 4).toLowerCase() != 'xn--') {
    return label;
  }
  return _decodePunycode(label.substring(4)) ?? label;
}

String? _decodePunycode(String input) {
  final delimiter = input.lastIndexOf('-');
  final output = <int>[];
  for (var index = 0; index < delimiter; index++) {
    final unit = input.codeUnitAt(index);
    if (unit >= 0x80) {
      return null;
    }
    output.add(unit);
  }
  var n = _initialN;
  var bias = _initialBias;
  var i = 0;
  var position = delimiter > 0 ? delimiter + 1 : 0;
  while (position < input.length) {
    final oldI = i;
    var weight = 1;
    for (var k = _base; ; k += _base) {
      if (position >= input.length) {
        return null;
      }
      final digit = _digitOf(input.codeUnitAt(position++));
      if (digit == null) {
        return null;
      }
      i += digit * weight;
      if (i > _maxCodePoint * (output.length + 1)) {
        return null;
      }
      final t = k <= bias
          ? _tMin
          : k >= bias + _tMax
          ? _tMax
          : k - bias;
      if (digit < t) {
        break;
      }
      weight *= _base - t;
    }
    final length = output.length + 1;
    bias = _adapt(i - oldI, length, first: oldI == 0);
    n += i ~/ length;
    i %= length;
    if (n > _maxCodePoint || (n >= 0xD800 && n <= 0xDFFF)) {
      return null;
    }
    output.insert(i++, n);
  }
  if (output.every((code) => code < 0x80) ||
      output.any((code) => code < 0x20 || (code >= 0x7F && code < 0xA0))) {
    return null;
  }
  return String.fromCharCodes(output);
}

int _adapt(int delta, int points, {required bool first}) {
  var scaled = first ? delta ~/ _damp : delta ~/ 2;
  scaled += scaled ~/ points;
  var k = 0;
  while (scaled > (_base - _tMin) * _tMax ~/ 2) {
    scaled ~/= _base - _tMin;
    k += _base;
  }
  return k + (_base - _tMin + 1) * scaled ~/ (scaled + _skew);
}

int? _digitOf(int unit) => switch (unit) {
  >= 0x30 && <= 0x39 => unit - 0x30 + 26,
  >= 0x41 && <= 0x5A => unit - 0x41,
  >= 0x61 && <= 0x7A => unit - 0x61,
  _ => null,
};
