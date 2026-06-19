#!/usr/bin/env bash
# Build Flutter web for production with PWA support (service worker for offline/install).
# Used by firebase deploy --only hosting predeploy.
set -e
cd "$(dirname "$0")/.."
flutter clean && flutter pub get
# --no-tree-shake-icons: required for font_awesome_flutter 11.x on web release builds
# https://github.com/fluttercommunity/font_awesome_flutter/issues/301
flutter build web --release --pwa-strategy offline-first --no-tree-shake-icons
