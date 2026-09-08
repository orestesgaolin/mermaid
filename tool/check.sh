#!/usr/bin/env bash
# Run from any directory; CI and release validation use the same commands.
set -euo pipefail
cd "$(dirname "$0")/.."

flutter pub get
dart analyze --fatal-infos
dart test packages/elk
dart test packages/mermaid_core
flutter test packages/mermaid_flutter
# The parity corpus generator under apps/demo/tool is an explicit macOS-only
# evidence command. CI runs the demo's real test directory.
flutter test apps/demo/test
flutter test apps/website
(cd packages/elk && dart pub publish --dry-run)
(cd packages/mermaid_core && dart pub publish --dry-run)
(cd packages/mermaid_flutter && flutter pub publish --dry-run)
