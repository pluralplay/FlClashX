import 'package:flutter/widgets.dart';

/// Marker widget to instruct CommonScaffold to place the search button at the end of actions.
class SearchOrderMarker extends StatelessWidget {
  const SearchOrderMarker({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
