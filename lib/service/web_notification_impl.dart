import 'dart:html' as html;

void requestWebPermission() {
  if (html.Notification.permission != 'granted') {
    html.Notification.requestPermission();
  }
}

void showWebNotification(String title, String body) {
  if (html.Notification.permission == 'granted') {
    html.Notification(title, body: body, icon: 'favicon.png');
  } else if (html.Notification.permission != 'denied') {
    html.Notification.requestPermission().then((permission) {
      if (permission == 'granted') {
        html.Notification(title, body: body, icon: 'favicon.png');
      }
    });
  }
}
