import 'package:web/web.dart' as web;

/// Opens a url in a new browser tab.
///
/// This is the web implementation of `browser_launcher_stub.dart`.
///
/// The call has to be synchronous: the browser only allows a new tab while
/// the user gesture (the tap) is still active. A delay before the call
/// means the popup blocker drops it.
bool openInNewTab(String url) {
  try {
    web.window.open(url, '_blank', 'noopener,noreferrer');
    return true;
  } catch (_) {
    return false;
  }
}
