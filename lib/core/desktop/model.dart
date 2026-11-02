import 'dart:async';
import 'dart:math';

enum CoreProcessOwner { direct, helper }

enum CoreLifecycleOutcome { applied, coalesced, superseded }

enum DesktopCorePhase { idle, starting, running, stopping, failed, closed }

final class CoreLifecycleResult {
  final int revision;
  final CoreLifecycleOutcome outcome;
  final DesktopCoreSession? session;

  const CoreLifecycleResult({
    required this.revision,
    required this.outcome,
    this.session,
  });
}

final class DesktopCoreTimeouts {
  final Duration ready;
  final Duration connection;
  final Duration disconnection;

  const DesktopCoreTimeouts({
    this.ready = const Duration(seconds: 10),
    this.connection = const Duration(seconds: 10),
    this.disconnection = const Duration(seconds: 10),
  });
}

final class CoreProcessStopResult {
  final bool stopped;
  final bool exitConfirmed;

  const CoreProcessStopResult({
    required this.stopped,
    required this.exitConfirmed,
  });

  @override
  bool operator ==(Object other) {
    return other is CoreProcessStopResult &&
        other.stopped == stopped &&
        other.exitConfirmed == exitConfirmed;
  }

  @override
  int get hashCode => Object.hash(stopped, exitConfirmed);
}

abstract interface class CoreProcessLease {
  String get sessionId;

  CoreProcessOwner get owner;

  int get pid;

  /// The first line of the crash report the Core last wrote, when this side
  /// can read its output; a Helper keeps that output in its own log.
  String? get crashHeadline;

  Future<CoreProcessStopResult> stop(Duration timeout);
}

final class DesktopCoreSession {
  final String sessionId;
  final CoreProcessLease lease;
  final int connectionGeneration;

  const DesktopCoreSession({
    required this.sessionId,
    required this.lease,
    required this.connectionGeneration,
  });

  CoreProcessOwner get owner => lease.owner;

  int get pid => lease.pid;
}

final class DesktopCoreFailure implements Exception {
  final String code;
  final DesktopCorePhase phase;
  final int revision;
  final String? sessionId;
  final CoreProcessOwner? owner;
  final int? pid;
  final int? connectionGeneration;
  final Object? cause;
  final String? crashHeadline;
  final StackTrace? stackTrace;

  const DesktopCoreFailure({
    required this.code,
    required this.phase,
    required this.revision,
    this.sessionId,
    this.owner,
    this.pid,
    this.connectionGeneration,
    this.cause,
    this.crashHeadline,
    this.stackTrace,
  });

  @override
  String toString() {
    return 'DesktopCoreFailure($code, $phase, revision: $revision, '
        'session: $sessionId, owner: $owner, pid: $pid, '
        'generation: $connectionGeneration, cause: $cause, '
        'crash: $crashHeadline)';
  }
}

sealed class DesktopCoreState {
  const DesktopCoreState();

  DesktopCorePhase get phase;
}

final class DesktopCoreIdle extends DesktopCoreState {
  const DesktopCoreIdle();

  @override
  DesktopCorePhase get phase => DesktopCorePhase.idle;
}

final class DesktopCoreStarting extends DesktopCoreState {
  const DesktopCoreStarting();

  @override
  DesktopCorePhase get phase => DesktopCorePhase.starting;
}

final class DesktopCoreRunning extends DesktopCoreState {
  final DesktopCoreSession session;

  const DesktopCoreRunning(this.session);

  @override
  DesktopCorePhase get phase => DesktopCorePhase.running;
}

final class DesktopCoreStopping extends DesktopCoreState {
  const DesktopCoreStopping();

  @override
  DesktopCorePhase get phase => DesktopCorePhase.stopping;
}

final class DesktopCoreFailed extends DesktopCoreState {
  const DesktopCoreFailed();

  @override
  DesktopCorePhase get phase => DesktopCorePhase.failed;
}

final class DesktopCoreClosed extends DesktopCoreState {
  const DesktopCoreClosed();

  @override
  DesktopCorePhase get phase => DesktopCorePhase.closed;
}

String createCoreSessionId() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}
