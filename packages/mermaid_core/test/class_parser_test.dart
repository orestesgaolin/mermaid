/// Class diagram parser tests; cases ported from upstream classDiagram.spec.ts
/// and classDb.spec.ts.
library;

import 'package:mermaid_core/src/diagrams/class_diagram/class_model.dart';
import 'package:mermaid_core/src/diagrams/class_diagram/class_parser.dart';
import 'package:mermaid_core/src/diagrams/flowchart/flow_model.dart'
    show FlowDirection;
import 'package:mermaid_core/src/parse_error.dart';
import 'package:test/test.dart';

ClassDiagram parse(String body) => parseClassDiagram('classDiagram\n$body');

void main() {
  group('class declarations', () {
    test('bare class', () {
      final d = parse('class Animal');
      expect(d.classes.keys, ['Animal']);
      expect(d.classes['Animal']!.label, 'Animal');
    });
    test('class with display label', () {
      final d = parse('class Animal["Living being"]');
      expect(d.classes['Animal']!.label, 'Living being');
    });
    test('implicit declaration via relation', () {
      final d = parse('Animal <|-- Duck');
      expect(d.classes.keys, containsAll(['Animal', 'Duck']));
    });
    test('generic class name', () {
      final d = parse('class List~T~');
      expect(d.classes.keys, ['List']);
      expect(d.classes['List']!.label, 'List<T>');
    });
    test('generic suffix declaration', () {
      final d = parse('class People List~List~Person~~');
      expect(d.classes['People']!.label, 'People List<List<Person>>');
    });
    test('classDiagram-v2 header accepted', () {
      expect(parseClassDiagram('classDiagram-v2\nclass A').classes.keys, ['A']);
    });
  });

  group('members', () {
    test('block body attributes and methods', () {
      final d = parse('class Animal {\n+String name\n-int age\n+eat(food) : bool\n}');
      final c = d.classes['Animal']!;
      expect(c.attributes.map((m) => m.text), ['+String name', '-int age']);
      expect(c.methods.map((m) => m.text), ['+eat(food) : bool']);
    });
    test('colon syntax', () {
      final d = parse('Animal : +String name\nAnimal : +eat()');
      final c = d.classes['Animal']!;
      expect(c.attributes.single.text, '+String name');
      expect(c.methods.single.text, '+eat()');
    });
    test('method detection by parenthesis', () {
      final d = parse('A : justAField\nA : method()');
      expect(d.classes['A']!.attributes.single.text, 'justAField');
      expect(d.classes['A']!.methods.single.text, 'method()');
    });
    test('visibility prefixes preserved', () {
      final d = parse('A : +pub\nA : -priv\nA : #prot\nA : ~pkg');
      expect(d.classes['A']!.attributes.map((m) => m.text),
          ['+pub', '-priv', '#prot', '~pkg']);
    });
    test('static and abstract classifiers', () {
      final d = parse(r'A : +instances() int$' '\nA : +area()*');
      expect(d.classes['A']!.methods[0].isStatic, isTrue);
      expect(d.classes['A']!.methods[1].isAbstract, isTrue);
      expect(d.classes['A']!.methods[1].text, '+area()');
    });
    test('generics converted in members', () {
      final d = parse('A : +List~int~ ids');
      expect(d.classes['A']!.attributes.single.text, '+List<int> ids');
    });
    test('annotation inside block', () {
      final d = parse('class Shape {\n<<interface>>\ndraw()\n}');
      expect(d.classes['Shape']!.annotations, ['interface']);
      expect(d.classes['Shape']!.methods.single.text, 'draw()');
    });
    test('annotation statement form', () {
      final d = parse('class Shape\n<<interface>> Shape');
      expect(d.classes['Shape']!.annotations, ['interface']);
    });
  });

  group('relations', () {
    ClassRelation rel(String stmt) => parse(stmt).relations.single;

    test('inheritance <|--', () {
      final r = rel('Animal <|-- Duck');
      expect(r.from, 'Animal');
      expect(r.to, 'Duck');
      expect(r.endFrom, RelationEnd.extension);
      expect(r.endTo, RelationEnd.none);
      expect(r.dotted, isFalse);
    });
    test('reversed inheritance --|>', () {
      final r = rel('Duck --|> Animal');
      expect(r.endTo, RelationEnd.extension);
    });
    test('composition *--', () {
      expect(rel('House *-- Room').endFrom, RelationEnd.composition);
    });
    test('aggregation o--', () {
      expect(rel('Pond o-- Duck').endFrom, RelationEnd.aggregation);
    });
    test('association -->', () {
      expect(rel('A --> B').endTo, RelationEnd.arrow);
    });
    test('plain link --', () {
      final r = rel('A -- B');
      expect(r.endFrom, RelationEnd.none);
      expect(r.endTo, RelationEnd.none);
    });
    test('dashed dependency ..>', () {
      final r = rel('A ..> B');
      expect(r.dotted, isTrue);
      expect(r.endTo, RelationEnd.arrow);
    });
    test('realization ..|>', () {
      final r = rel('A ..|> B');
      expect(r.dotted, isTrue);
      expect(r.endTo, RelationEnd.extension);
    });
    test('dashed link ..', () {
      expect(rel('A .. B').dotted, isTrue);
    });
    test('two-way <|--|>', () {
      final r = rel('A <|--|> B');
      expect(r.endFrom, RelationEnd.extension);
      expect(r.endTo, RelationEnd.extension);
    });
    test('lollipop ()--', () {
      expect(rel('A ()-- B').endFrom, RelationEnd.lollipop);
    });
    test('cardinalities', () {
      final r = rel('Customer "1" --> "*" Ticket');
      expect(r.cardFrom, '1');
      expect(r.cardTo, '*');
    });
    test('label', () {
      expect(rel('A --> B : uses').label, 'uses');
    });
    test('label and cardinalities together', () {
      final r = rel('Galaxy --> "many" Star : contains');
      expect(r.cardTo, 'many');
      expect(r.label, 'contains');
    });
  });

  group('structure statements', () {
    test('direction', () {
      expect(parse('direction LR\nclass A').direction, FlowDirection.lr);
    });
    test('namespace membership', () {
      final d = parse('namespace Shapes {\nclass Circle\nclass Square\n}');
      expect(d.namespaces.single.id, 'Shapes');
      expect(d.namespaces.single.classIds, ['Circle', 'Square']);
    });
    test('nested namespaces', () {
      final d = parse(
          'namespace Outer {\nnamespace Inner {\nclass A\n}\nclass B\n}');
      expect(d.namespaces.length, 2);
      final outer = d.namespaces.firstWhere((n) => n.id == 'Outer');
      expect(outer.classIds, containsAll(['A', 'B']));
    });
    test('namespace with label', () {
      final d = parse('namespace Auth["Authentication Service"] {\nclass A\n}');
      expect(d.namespaces.single.label, 'Authentication Service');
    });
    test('note for class', () {
      final d = parse('class A\nnote for A "important"');
      expect(d.notes.single.forClass, 'A');
      expect(d.notes.single.text, 'important');
    });
    test('floating note', () {
      expect(parse('note "hello"').notes.single.forClass, isNull);
    });
    test('cssClass and classDef', () {
      final d = parse('class A:::hot\nclassDef hot fill:#f96');
      expect(d.classes['A']!.cssClasses, ['hot']);
      expect(d.classDefs['hot'], {'fill': '#f96'});
    });
    test('style statement', () {
      final d = parse('class A\nstyle A fill:#bbf,stroke:#33f');
      expect(d.classes['A']!.styles['fill'], '#bbf');
    });
    test('link stores url', () {
      final d = parse('class A\nlink A "https://example.com"');
      expect(d.classes['A']!.link, 'https://example.com');
    });
    test('frontmatter title', () {
      final d = parseClassDiagram('---\ntitle: Animals\n---\nclassDiagram\nclass A');
      expect(d.title, 'Animals');
    });
    test('comments ignored', () {
      final d = parse('%% top comment\nclass A %% trailing');
      expect(d.classes.keys, ['A']);
    });
    test('garbage throws with line number', () {
      expect(
        () => parse('class A\n!!nonsense!!'),
        throwsA(isA<MermaidParseException>()
            .having((e) => e.line, 'line', isNotNull)),
      );
    });
  });
}
