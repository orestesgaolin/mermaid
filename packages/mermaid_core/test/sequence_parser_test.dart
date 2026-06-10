/// Sequence parser tests; cases ported from upstream sequenceDiagram.spec.js.
library;

import 'package:mermaid_core/src/diagrams/sequence/sequence_model.dart';
import 'package:mermaid_core/src/diagrams/sequence/sequence_parser.dart';
import 'package:mermaid_core/src/parse_error.dart';
import 'package:test/test.dart';

SequenceDiagram parse(String body) => parseSequence('sequenceDiagram\n$body');

void main() {
  group('participants', () {
    test('implicit declaration in first-mention order', () {
      final d = parse('Alice->Bob: Hello Bob, how are you?');
      expect(d.participants.keys, ['Alice', 'Bob']);
    });
    test('explicit declaration order wins', () {
      final d = parse('participant Bob\nparticipant Alice\nAlice->Bob: hi');
      expect(d.participants.keys, ['Bob', 'Alice']);
    });
    test('alias', () {
      final d = parse('participant A as Alice in Wonderland\nA->B: hi');
      expect(d.participants['A']!.label, 'Alice in Wonderland');
    });
    test('actor keyword', () {
      final d = parse('actor Alice\nAlice->Bob: hi');
      expect(d.participants['Alice']!.isActor, isTrue);
      expect(d.participants['Bob']!.isActor, isFalse);
    });
    test('create participant registers', () {
      final d = parse('Alice->Bob: hi\ncreate participant Carl\nAlice->Carl: hi');
      expect(d.participants.keys, contains('Carl'));
    });
    test('box groups are tolerated', () {
      final d = parse(
          'box Group A\nparticipant A\nparticipant B\nend\nA->B: hi');
      expect(d.participants.keys, ['A', 'B']);
      expect(d.events.whereType<SeqMessage>().length, 1);
    });
  });

  group('messages', () {
    SeqMessage single(String stmt) =>
        parse(stmt).events.whereType<SeqMessage>().single;

    test('solid open ->', () {
      expect(single('A->B: t').arrow, SeqArrow.solidOpen);
    });
    test('dotted open -->', () {
      expect(single('A-->B: t').arrow, SeqArrow.dottedOpen);
    });
    test('solid arrow ->>', () {
      expect(single('A->>B: t').arrow, SeqArrow.solidArrow);
    });
    test('dotted arrow -->>', () {
      expect(single('A-->>B: t').arrow, SeqArrow.dottedArrow);
    });
    test('bidirectional solid <<->>', () {
      expect(single('A<<->>B: t').arrow, SeqArrow.bidirectionalSolid);
    });
    test('bidirectional dotted <<-->>', () {
      expect(single('A<<-->>B: t').arrow, SeqArrow.bidirectionalDotted);
    });
    test('solid cross -x', () {
      expect(single('A-xB: t').arrow, SeqArrow.solidCross);
    });
    test('dotted cross --x', () {
      expect(single('A--xB: t').arrow, SeqArrow.dottedCross);
    });
    test('solid async -)', () {
      expect(single('A-)B: t').arrow, SeqArrow.solidPoint);
    });
    test('dotted async --)', () {
      expect(single('A--)B: t').arrow, SeqArrow.dottedPoint);
    });
    test('text and spacing', () {
      final m = single('Alice ->> Bob : Hello Bob, how are you?');
      expect(m.from, 'Alice');
      expect(m.to, 'Bob');
      expect(m.text, 'Hello Bob, how are you?');
    });
    test('message without text', () {
      final m = single('A->>B');
      expect(m.text, isEmpty);
    });
    test('br tags become newlines', () {
      expect(single('A->>B: line1<br/>line2').text, 'line1\nline2');
    });
    test('self message', () {
      final m = single('A->>A: thinking');
      expect(m.from, 'A');
      expect(m.to, 'A');
    });
    test('statement order preserved', () {
      final d = parse('A->>B: one\nB-->>A: two\nA-xC: three');
      final texts =
          d.events.whereType<SeqMessage>().map((m) => m.text).toList();
      expect(texts, ['one', 'two', 'three']);
    });
  });

  group('activations', () {
    test('+ suffix activates receiver after message', () {
      final d = parse('A->>+B: go');
      expect(d.events[0], isA<SeqMessage>());
      final act = d.events[1] as SeqActivation;
      expect(act.id, 'B');
      expect(act.active, isTrue);
    });
    test('- suffix deactivates sender', () {
      final d = parse('A->>+B: go\nB-->>-A: done');
      final act = d.events.whereType<SeqActivation>().last;
      expect(act.id, 'B');
      expect(act.active, isFalse);
    });
    test('explicit activate/deactivate statements', () {
      final d = parse('A->>B: go\nactivate B\ndeactivate B');
      final acts = d.events.whereType<SeqActivation>().toList();
      expect(acts.length, 2);
      expect(acts[0].active, isTrue);
      expect(acts[1].active, isFalse);
    });
    test('nested activations allowed', () {
      final d = parse('A->>+B: a\nA->>+B: b\nB-->>-A: c\nB-->>-A: d');
      expect(d.events.whereType<SeqActivation>().length, 4);
    });
    test('deactivating inactive participant throws', () {
      expect(() => parse('A->>B: go\ndeactivate B'),
          throwsA(isA<MermaidParseException>()));
    });
  });

  group('notes', () {
    SeqNote note(String stmt) =>
        parse('A->>B: x\n$stmt').events.whereType<SeqNote>().single;

    test('right of', () {
      final n = note('Note right of A: hi');
      expect(n.placement, NotePlacement.rightOf);
      expect(n.target, 'A');
      expect(n.text, 'hi');
    });
    test('left of', () {
      expect(note('Note left of B: hi').placement, NotePlacement.leftOf);
    });
    test('over single', () {
      final n = note('Note over A: hi');
      expect(n.placement, NotePlacement.over);
      expect(n.target2, isNull);
    });
    test('over two participants', () {
      final n = note('Note over A,B: spanning');
      expect(n.target, 'A');
      expect(n.target2, 'B');
    });
    test('lowercase note keyword', () {
      expect(note('note over A: hi').text, 'hi');
    });
  });

  group('blocks', () {
    test('loop', () {
      final d = parse('loop every minute\nA->>B: ping\nend');
      final start = d.events.first as SeqBlockStart;
      expect(start.kind, SeqBlockKind.loop);
      expect(start.label, 'every minute');
      expect(d.events.last, isA<SeqBlockEnd>());
    });
    test('alt/else', () {
      final d = parse('alt ok\nA->>B: yes\nelse not ok\nA->>B: no\nend');
      expect((d.events.first as SeqBlockStart).kind, SeqBlockKind.alt);
      expect(d.events.whereType<SeqBlockDivider>().single.label, 'not ok');
    });
    test('par/and', () {
      final d = parse('par one\nA->>B: a\nand two\nA->>C: b\nend');
      expect((d.events.first as SeqBlockStart).kind, SeqBlockKind.par);
      expect(d.events.whereType<SeqBlockDivider>().single.label, 'two');
    });
    test('critical/option', () {
      final d = parse('critical connect\nA->>B: a\noption timeout\nA->>B: b\nend');
      expect((d.events.first as SeqBlockStart).kind, SeqBlockKind.critical);
    });
    test('opt and break', () {
      expect((parse('opt maybe\nA->>B: a\nend').events.first as SeqBlockStart)
          .kind, SeqBlockKind.opt);
      expect((parse('break oops\nA->>B: a\nend').events.first as SeqBlockStart)
          .kind, SeqBlockKind.breakBlock);
    });
    test('rect with color', () {
      final start = parse('rect rgb(200, 220, 255)\nA->>B: a\nend')
          .events.first as SeqBlockStart;
      expect(start.kind, SeqBlockKind.rect);
      expect(start.color, 'rgb(200, 220, 255)');
    });
    test('nesting', () {
      final d = parse(
          'loop outer\nalt x\nA->>B: a\nelse y\nA->>B: b\nend\nend');
      expect(d.events.whereType<SeqBlockStart>().length, 2);
      expect(d.events.whereType<SeqBlockEnd>().length, 2);
    });
    test('else outside alt throws', () {
      expect(() => parse('loop x\nelse y\nend'),
          throwsA(isA<MermaidParseException>()));
    });
    test('unclosed block throws', () {
      expect(() => parse('loop x\nA->>B: a'),
          throwsA(isA<MermaidParseException>()));
    });
  });

  group('misc', () {
    test('autonumber plain', () {
      final a = parse('autonumber\nA->>B: x').events.first as SeqAutonumber;
      expect(a.on, isTrue);
      expect(a.start, isNull);
    });
    test('autonumber with start and step', () {
      final a = parse('autonumber 10 5\nA->>B: x').events.first as SeqAutonumber;
      expect(a.start, 10);
      expect(a.step, 5);
    });
    test('autonumber off', () {
      final a = parse('autonumber off').events.first as SeqAutonumber;
      expect(a.on, isFalse);
    });
    test('title statement', () {
      expect(parse('title My Title\nA->>B: x').title, 'My Title');
    });
    test('frontmatter title', () {
      final d = parseSequence(
          '---\ntitle: Front Title\n---\nsequenceDiagram\nA->>B: x');
      expect(d.title, 'Front Title');
    });
    test('comments ignored', () {
      final d = parse('%% a comment\nA->>B: x %% trailing');
      expect(d.events.whereType<SeqMessage>().single.text, 'x');
    });
    test('accTitle/accDescr tolerated', () {
      final d = parse('accTitle: t\naccDescr: d\nA->>B: x');
      expect(d.events.whereType<SeqMessage>().length, 1);
    });
    test('init directive stripped', () {
      final d = parseSequence(
          '%%{init: {"theme": "dark"}}%%\nsequenceDiagram\nA->>B: x');
      expect(d.events.whereType<SeqMessage>().length, 1);
    });
    test('garbage statement throws with line number', () {
      expect(
        () => parse('A->>B: ok\nthis is nonsense'),
        throwsA(isA<MermaidParseException>()
            .having((e) => e.line, 'line', isNotNull)),
      );
    });
    test('non-sequence source throws', () {
      expect(() => parseSequence('graph TD\nA-->B'),
          throwsA(isA<MermaidParseException>()));
    });
  });
}
