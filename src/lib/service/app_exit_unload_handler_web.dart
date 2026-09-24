// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

/// Registers browser page unload hooks for best-effort shutdown.
void registerAppExitUnloadHandler(void Function() onUnload) {
  html.window.onPageHide.listen((_) {
    onUnload();
  });
  html.window.onBeforeUnload.listen((_) {
    onUnload();
  });
}
