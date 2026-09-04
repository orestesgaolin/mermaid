import 'dart:io';

/// Locates the `mermaid_core` package directory so fixture reads work both
/// from inside the package (`dart test`) and from the workspace root
/// (`dart test packages/mermaid_core`, which is what CI runs).
final Directory _packageRoot = _findPackageRoot();

Directory _findPackageRoot() {
  final cwd = Directory.current;
  final candidates = <Directory>[
    cwd,
    Directory('${cwd.path}/packages/mermaid_core'),
  ];
  for (final dir in candidates) {
    final pubspec = File('${dir.path}/pubspec.yaml');
    if (!pubspec.existsSync()) continue;
    if (!pubspec.readAsStringSync().contains('name: mermaid_core')) continue;
    if (Directory('${dir.path}/test/fixtures').existsSync()) return dir;
  }
  throw StateError(
    'Cannot locate the mermaid_core package from ${cwd.path}. '
    'Run tests from the package directory or the workspace root.',
  );
}

/// Absolute path of a file under `test/fixtures`.
String fixturePath(String relative) =>
    '${_packageRoot.path}/test/fixtures/$relative';

/// Reads a file under `test/fixtures` as a string.
String readFixture(String relative) =>
    File(fixturePath(relative)).readAsStringSync();
