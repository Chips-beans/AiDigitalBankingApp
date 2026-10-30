import 'package:web/web.dart' as web;

bool openSupportEmail() {
  web.window.open(
    'mailto:reachsteav2@gmail.com?subject=Kesor%20Bank%20support',
    '_self',
  );
  return true;
}
