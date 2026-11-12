import 'package:fl_clash/common/punycode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shows every xn-- label as the Unicode it encodes', () {
    expect(decodeIdnHost('xn--41a.xn--p1acf'), 'я.рус');
    expect(decodeIdnHost('xn--d1acpjx3f.xn--p1ai'), 'яндекс.рф');
    expect(decodeIdnHost('www.xn--mnchen-3ya.de'), 'www.münchen.de');
    expect(decodeIdnHost('XN--P1AI'), 'рф');
  });

  test('keeps the basic letters before the last delimiter', () {
    expect(decodeIdnHost('xn--bcher-kva.example'), 'bücher.example');
  });

  test('leaves a host without an xn-- label as it is', () {
    expect(decodeIdnHost('example.com'), 'example.com');
    expect(decodeIdnHost('axn--b.com'), 'axn--b.com');
    expect(decodeIdnHost('1.1.1.1'), '1.1.1.1');
  });

  test('keeps a label that does not decode', () {
    expect(decodeIdnHost('xn--.com'), 'xn--.com');
    expect(decodeIdnHost('xn--ab!.com'), 'xn--ab!.com');
    expect(decodeIdnHost('xn--99999999999.com'), 'xn--99999999999.com');
    expect(decodeIdnHost('xn--a.xn--p1ai'), 'xn--a.рф');
    expect(decodeIdnHost('xn--abc-.com'), 'xn--abc-.com');
    final long = 'xn--${'z' * 60}';
    expect(decodeIdnHost('$long.com'), '$long.com');
  });
}
