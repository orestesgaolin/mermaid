/// Locates the Dart workspace root from any working directory.
///
/// Tests and generators must not build output paths relative to
/// `Directory.current`: `flutter test` can be started from `apps/demo` or from
/// the workspace root, and a relative `../../` path silently resolves outside
/// the repository in the second case.
library;

import 'dart:io';

/// The `name:` of the root `pubspec.yaml` of this workspace.
const workspacePubspecName = '_mermaid_dart_workspace';

/// Walks up from [Directory.current] until it finds the directory whose
/// `pubspec.yaml` declares `name: _mermaid_dart_workspace`.
///
/// Throws a [StateError] with the inspected path when no such directory
/// exists, so a misconfigured run fails instead of writing somewhere random.
Directory workspaceRoot() {
  final start = Directory.current.absolute;
  var current = start;
  while (true) {
    if (_isWorkspaceRoot(current)) return current;
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError(
        'Could not locate the Mermaid workspace root: no ancestor of '
        '"${start.path}" has a pubspec.yaml declaring '
        '"name: $workspacePubspecName".',
      );
    }
    current = parent;
  }
}

bool _isWorkspaceRoot(Directory directory) {
  final pubspec = File('${directory.path}/pubspec.yaml');
  if (!pubspec.existsSync()) return false;
  return pubspec.readAsLinesSync().any(
    (line) => line.trimRight() == 'name: $workspacePubspecName',
  );
}
