/// `</br>` breaks a label line where mermaid.js 12 breaks it (#95).
library;

import 'package:mermaid_core/mermaid_core.dart';
import 'package:test/test.dart';

import 'support/scene.dart';

const _renderer = Mermaid(measurer: ApproximateTextMeasurer());

List<String> _texts(String source) => [
  for (final t in textsOf(_renderer.render(source).nodes)) t.text,
];

/// A painted text of [source] shows [first] and, on the next line,
/// [second], and no painted text keeps the tag.
void _expectTwoLines(
  String source, {
  String first = 'first line',
  String second = 'second line',
}) {
  final texts = _texts(source);
  expect(texts, isNot(contains(contains('br'))));
  expect(texts, contains(contains('$first\n$second')));
}

void main() {
  test('flowchart node and edge labels break at </br>', () {
    const source = '''
flowchart TD
  A["first line</br>second line"] -- "edge one</BR>edge two" --> B
''';
    _expectTwoLines(source);
    _expectTwoLines(source, first: 'edge one', second: 'edge two');
  });

  test('classDiagram, stateDiagram and erDiagram labels break at </br>', () {
    _expectTwoLines('classDiagram\n  class A["first line</br>second line"]\n');
    _expectTwoLines('stateDiagram-v2\n  s1 : first line</br>second line\n');
    _expectTwoLines('erDiagram\n  A["first line</br>second line"]\n');
  });

  test('sequence messages and notes break at </br>', () {
    const source = '''
sequenceDiagram
  Alice->>Bob: first line</br>second line
  Note over Alice,Bob: note one</br>note two
''';
    _expectTwoLines(source);
    _expectTwoLines(source, first: 'note one', second: 'note two');
  });

  test('C4 labels break at </br> and <br />', () {
    const source = '''
C4Context
  Person(a, "first line</br>second line", "desc one<br />desc two")
''';
    _expectTwoLines(source);
    _expectTwoLines(source, first: 'desc one', second: 'desc two');
  });

  test('timeline events keep </br> as text and break at <br>', () {
    final texts = _texts('''
timeline
  2020 : one</br>two
  2021 : three<br>four
''');
    expect(texts, contains('one</br>two'));
    expect(texts, contains('three\nfour'));
  });
}
