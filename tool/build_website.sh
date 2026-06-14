#!/bin/zsh
# Builds the comparison website. The Flutter renderer is embedded via
# jaspr_flutter_embed, so `jaspr build` runs the Flutter web build internally —
# no separate `flutter build web` step. Output: apps/website/build/jaspr.
set -e
cd "$(dirname "$0")/.."
(cd apps/website && jaspr build)
echo "Done: apps/website/build/jaspr"
