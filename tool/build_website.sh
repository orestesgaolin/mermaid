#!/bin/zsh
# Builds the comparison website: Flutter web embed first, then the static
# Jaspr site. Output: apps/website/build/jaspr (deployable as-is).
set -e
cd "$(dirname "$0")/.."
(cd apps/flutter_embed && flutter build web --release --pwa-strategy=none -o ../website/web/flutter_embed)
(cd apps/website && jaspr build)
echo "Done: apps/website/build/jaspr"
