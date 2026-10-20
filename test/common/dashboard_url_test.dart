import 'package:fl_clash/common/common.dart';
import 'package:test/test.dart';

void main() {
  test('the dashboard link carries the address and secret it connects to', () {
    expect(
      zashboardUrl('127.0.0.1:9091', secret: 'a b&c'),
      'http://127.0.0.1:9091/ui/#/setup?hostname=127.0.0.1&port=9091'
      '&secret=a+b%26c',
    );
  });

  test('a controller on every interface is reached over loopback', () {
    expect(
      zashboardUrl('0.0.0.0:9090'),
      'http://127.0.0.1:9090/ui/#/setup?hostname=127.0.0.1&port=9090',
    );
    expect(
      zashboardUrl('[::]:9090'),
      'http://127.0.0.1:9090/ui/#/setup?hostname=127.0.0.1&port=9090',
    );
  });

  test('an IPv6 host keeps its brackets in the origin only', () {
    expect(
      zashboardUrl('[::1]:9090'),
      'http://[::1]:9090/ui/#/setup?hostname=%3A%3A1&port=9090',
    );
  });
}
