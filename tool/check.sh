#!/usr/bin/env bash
# Run from any directory; CI and release validation use the same commands.
set -euo pipefail
cd "$(dirname "$0")/.."

flutter pub get
dart analyze --fatal-infos
dart test packages/elk
dart test packages/mermaid_core
flutter test packages/mermaid_flutter
flutter test apps/demo
flutter test apps/website
(cd packages/mermaid_core && dart pub publish --dry-run)
(cd packages/mermaid_flutter && flutter pub publish --dry-run)
