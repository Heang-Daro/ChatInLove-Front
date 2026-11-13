import 'dart:html' as html;

Future<void> registerServiceWorker() async {
  try {
    final serviceWorker = html.window.navigator.serviceWorker;
    if (serviceWorker == null) return;
    await serviceWorker.register('/sw.js');
  } catch (_) {
    // The browser may not support service workers or the page may be opened
    // in a restricted context. This is optional and should never crash the app.
  }
}

Future<bool> requestWebPermission() async {
  try {
    final permission = html.Notification.permission;
    if (permission == 'granted') return true;
    if (permission == 'denied') return false;

    final result = await html.Notification.requestPermission();
    return result == 'granted';
  } catch (_) {
    return false;
  }
}

void showWebNotification(String title, String body) {
  try {
    if (html.Notification.permission != 'granted') return;
    html.Notification(
      title,
      body: body,
      icon: '/icons/Icon-192.png',
    );
  } catch (_) {
    // Ignore browser-specific incompatibilities.
  }
}
