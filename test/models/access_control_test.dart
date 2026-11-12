import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:test/test.dart';

void main() {
  const accepting = AccessControlProps(
    enable: true,
    mode: AccessControlMode.acceptSelected,
    acceptList: ['a.app'],
    rejectList: ['r.app'],
  );
  const rejecting = AccessControlProps(
    enable: true,
    acceptList: ['a.app'],
    rejectList: ['r.app'],
  );

  test('no profile lists leave the picked apps alone', () {
    expect(
      accepting.withPackages(include: const [], exclude: const []),
      same(accepting),
    );
  });

  test('picked apps outside the profile include list stay out', () {
    final props = accepting
        .copyWith(acceptList: ['a.app', 'p.app'])
        .withPackages(include: const ['p.app', 'q.app'], exclude: const []);

    expect(props.mode, AccessControlMode.acceptSelected);
    expect(props.acceptList, ['p.app']);
  });

  test('a profile excluded app stays out even when picked', () {
    final props = accepting
        .copyWith(acceptList: ['a.app', 'x.app'])
        .withPackages(include: const [], exclude: const ['x.app']);

    expect(props.mode, AccessControlMode.acceptSelected);
    expect(props.acceptList, ['a.app']);
  });

  test('profile excluded apps join the rejected ones', () {
    final props = rejecting.withPackages(
      include: const [],
      exclude: const ['x.app'],
    );

    expect(props.mode, AccessControlMode.rejectSelected);
    expect(props.rejectList, ['r.app', 'x.app']);
  });

  test('rejected apps and the exclude list narrow the include list', () {
    final props = rejecting.withPackages(
      include: const ['p.app', 'r.app', 'x.app'],
      exclude: const ['x.app'],
    );

    expect(props.mode, AccessControlMode.acceptSelected);
    expect(props.acceptList, ['p.app']);
  });

  test('switched off access control takes only the profile lists', () {
    final off = accepting.copyWith(enable: false);

    final rejected = off.withPackages(
      include: const [],
      exclude: const ['x.app'],
    );
    expect(rejected.enable, isTrue);
    expect(rejected.mode, AccessControlMode.rejectSelected);
    expect(rejected.rejectList, ['x.app']);

    final accepted = off.withPackages(
      include: const ['p.app', 'x.app'],
      exclude: const ['x.app'],
    );
    expect(accepted.mode, AccessControlMode.acceptSelected);
    expect(accepted.acceptList, ['p.app']);
  });
}
