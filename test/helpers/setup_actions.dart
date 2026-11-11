import 'package:fl_clash/providers/action.dart';

class ApplyRecordingSetupAction extends SetupAction {
  int applyCount = 0;

  @override
  void applyProfileDebounce({bool silence = false, bool force = false}) {
    applyCount++;
  }
}
