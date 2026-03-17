import 'package:flutter/material.dart';

import '../common/common.dart';

class NullStatus extends StatelessWidget {

  const NullStatus({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Center(
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleMedium?.toBold,
        textAlign: TextAlign.center,
      ),
    );
}
