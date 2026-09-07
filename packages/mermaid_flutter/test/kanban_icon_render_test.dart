import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mermaid_flutter/mermaid_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Kanban registered icon changes Flutter PNG output', () async {
    const withIcon = '''
kanban
  todo[To Do]
    task[Ship release]
    task@{
      icon: "icon:star"
      ticket: "ABC-1"
    }
''';
    const missingIcon = '''
kanban
  todo[To Do]
    task[Ship release]
    task@{
      icon: "missing:not-registered"
      ticket: "ABC-1"
    }
''';

    final rendered = await renderToPng(withIcon, pixelRatio: 2);
    final fallback = await renderToPng(missingIcon, pixelRatio: 2);
    expect(rendered, isNot(equals(fallback)));

    final evidenceDirectory = Platform.environment['MERMAID_EVIDENCE_DIR'];
    if (evidenceDirectory != null) {
      final directory = Directory(evidenceDirectory)
        ..createSync(recursive: true);
      File('${directory.path}/kanban-icon.png').writeAsBytesSync(rendered);
      File(
        '${directory.path}/kanban-icon-missing.png',
      ).writeAsBytesSync(fallback);
    }
  });
}
