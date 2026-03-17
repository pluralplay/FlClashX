import 'package:flutter/cupertino.dart';

class CommonView extends StatefulWidget {

  const CommonView({
    super.key,
    required this.actions,
  });
  final List<Widget> actions;

  @override
  State<CommonView> createState() => _CommonViewState();
}

class _CommonViewState extends State<CommonView> {
  @override
  Widget build(BuildContext context) => const Placeholder();
}
