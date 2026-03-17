import 'package:flutter/material.dart';

class FloatLayout extends StatelessWidget {

  const FloatLayout({
    super.key,
    required this.floatingWidget,
    required this.child,
  });
  final Widget floatingWidget;

  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
      fit: StackFit.loose,
      children: [
        Center(
          child: child,
        ),
        Positioned(
          bottom: 0,
          right: 0,
          child: Container(
            child: floatingWidget,
          ),
        ),
      ],
    );
}

class FloatWrapper extends StatelessWidget {

  const FloatWrapper({
    super.key,
    required this.child,
  });
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
      margin: const EdgeInsets.all(kFloatingActionButtonMargin),
      child: child,
    );
}
