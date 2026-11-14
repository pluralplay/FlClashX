#include "my_application.h"

#ifdef GDK_WINDOWING_X11
#include <X11/Xlib.h>
#endif

int main(int argc, char** argv) {
#ifdef GDK_WINDOWING_X11
  // libX11 enables its own locking only from 1.8 on; on older releases the
  // tray indicator reaching X11 from another thread aborts the process.
  XInitThreads();
#endif
  g_autoptr(MyApplication) app = my_application_new();
  // Dart asks the running app over its own channel; a unique application would
  // forward this launch to the running instance, which only raises its window.
  for (int i = 1; i < argc; i++) {
    if (g_strcmp0(argv[i], "--restart-core") == 0) {
      g_application_set_flags(G_APPLICATION(app),
                              G_APPLICATION_HANDLES_COMMAND_LINE | G_APPLICATION_NON_UNIQUE);
      break;
    }
  }
  return g_application_run(G_APPLICATION(app), argc, argv);
}
