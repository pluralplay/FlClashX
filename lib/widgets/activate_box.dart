import 'package:flutter/material.dart';

class ActivateBox extends StatelessWidget {

  const ActivateBox({
    super.key,
    required this.child,
    this.active = false,
  });
  final Widget child;
  final bool active;

  @override
  Widget build(BuildContext context) => IgnorePointer(
      ignoring: !active,
      child: child,
    );
}
