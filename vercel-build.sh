#!/usr/bin/env bash
set -euo pipefail

# Install Flutter stable in the Vercel build environment when it is not present.
if [ ! -x "flutter/bin/flutter" ]; then
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 flutter
fi

./flutter/bin/flutter pub get
./flutter/bin/flutter build web --release
