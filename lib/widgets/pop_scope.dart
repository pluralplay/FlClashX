import 'dart:async';

import 'package:flclashx/state.dart';
import 'package:flutter/widgets.dart';

class CommonPopScope extends StatelessWidget {

  const CommonPopScope({
    super.key,
    required this.child,
    this.onPop,
  });
  final Widget child;
  final FutureOr<bool> Function()? onPop;

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: onPop == null ? true : false,
      onPopInvokedWithResult: onPop == null
          ? null
          : (didPop, __) async {
              if (didPop) {
                return;
              }
              final res = await onPop!();
              if (!context.mounted) {
                return;
              }
              if (!res) {
                return;
              }
              Navigator.of(context).pop();
            },
      child: child,
    );
}

class SystemBackBlock extends StatefulWidget {

  const SystemBackBlock({
    super.key,
    required this.child,
  });
  final Widget child;

  @override
  State<SystemBackBlock> createState() => _SystemBackBlockState();
}

class _SystemBackBlockState extends State<SystemBackBlock> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      globalState.appController.backBlock();
    });
  }

  @override
  void dispose() {
    super.dispose();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      globalState.appController.unBackBlock();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
