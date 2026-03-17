import 'package:flclashx/common/common.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flutter/scheduler.dart';

class Render {

  factory Render() {
    _instance ??= Render._internal();
    return _instance!;
  }

  Render._internal();
  static Render? _instance;
  bool _isPaused = false;
  final _dispatcher = SchedulerBinding.instance.platformDispatcher;
  FrameCallback? _beginFrame;
  VoidCallback? _drawFrame;

  void active() {
    resume();
    pause();
  }

  void pause() {
    throttler.call(
      FunctionTag.renderPause,
      _pause,
      duration: const Duration(seconds: 5),
    );
  }

  void resume() {
    throttler.cancel(FunctionTag.renderPause);
    _resume();
  }

  void _pause() async {
    if (_isPaused) return;
    _isPaused = true;
    _beginFrame = _dispatcher.onBeginFrame;
    _drawFrame = _dispatcher.onDrawFrame;
    _dispatcher.onBeginFrame = null;
    _dispatcher.onDrawFrame = null;
    commonPrint.log("pause");
  }

  void _resume() {
    if (!_isPaused) return;
    _isPaused = false;
    _dispatcher.onBeginFrame = _beginFrame;
    _dispatcher.onDrawFrame = _drawFrame;
    _dispatcher.scheduleFrame();
    commonPrint.log("resume");
  }
}

final Render? render = system.isDesktop ? Render() : null;
