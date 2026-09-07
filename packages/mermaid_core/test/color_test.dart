import 'support/scene.dart';
import 'package:mermaid_core/mermaid_core.dart';
import 'package:test/test.dart';

void main() {
  group('Color.tryParse', () {
    test('parses CSS hex ordering and named colors', () {
      expect(Color.tryParse('#123'), const Color(0xff112233));
      expect(Color.tryParse('#1238'), const Color(0x88112233));
      expect(Color.tryParse('#123456'), const Color(0xff123456));
      expect(Color.tryParse('#12345680'), const Color(0x80123456));
      expect(Color.tryParse('RebeccaPurple'), const Color(0xff663399));
      expect(Color.tryParse('lightgoldenrodyellow'), const Color(0xfffafad2));
      expect(Color.tryParse('transparent'), Color.transparent);
    });

    test('parses numeric and percentage RGB channels', () {
      expect(Color.tryParse('rgb(255, 0, 128)'), const Color(0xffff0080));
      expect(Color.tryParse('rgb(100% 0% 50%)'), const Color(0xffff0080));
      expect(Color.tryParse('rgba(300,-2,128,50%)'), const Color(0x80ff0080));
      expect(Color.tryParse('rgb(255 0 128 / .25)'), const Color(0x40ff0080));
    });

    test('parses HSL, alpha, wrapping hue, and hue units', () {
      expect(Color.tryParse('hsl(0, 100%, 50%)'), const Color(0xffff0000));
      expect(Color.tryParse('hsl(120 100% 25%)'), const Color(0xff008000));
      expect(Color.tryParse('hsla(240,100%,50%,.5)'), const Color(0x800000ff));
      expect(
        Color.tryParse('hsl(-120deg 100% 50% / 25%)'),
        const Color(0x400000ff),
      );
      expect(Color.tryParse('hsl(.5turn 100% 50%)'), const Color(0xff00ffff));
      expect(Color.tryParse('hsl(200grad 100% 50%)'), const Color(0xff00ffff));
    });

    test('clamps valid values and rejects invalid syntax or numbers', () {
      expect(Color.tryParse('rgb(-10 300 0 / 2)'), const Color(0xff00ff00));
      expect(Color.tryParse('hsl(0 200% -10% / -1)'), Color.transparent);
      expect(Color.tryParse('rgba(1,2,3,nope)'), isNull);
      expect(Color.tryParse('rgb(1,2)'), isNull);
      expect(Color.tryParse('hsla(0,100%,50%)'), isNull);
      expect(Color.tryParse('hsl(0, 1, 0.5)'), isNull);
      expect(Color.tryParse('rgb(NaN 0 0)'), isNull);
    });
  });

  test('CSS colors flow through styles, Sankey config, and theme variables', () {
    const mermaid = Mermaid(measurer: ApproximateTextMeasurer());
    final flow = mermaid.render(
      'flowchart LR\nA[Styled]\nstyle A fill:hsl(120 100% 25%)',
    );
    expect(
      flattenScene(
        flow.nodes,
      ).whereType<SceneShape>().map((shape) => shape.fill?.color),
      contains(const Color(0xff008000)),
    );

    final sankey = mermaid.render('''
---
config:
  sankey:
    nodeColors: {A: rebeccapurple}
---
sankey-beta
A,B,1
''');
    expect(
      flattenScene(
        sankey.nodes,
      ).whereType<SceneShape>().map((shape) => shape.fill?.color),
      contains(const Color(0xff663399)),
    );

    final themed = mermaid.render(
      '''%%{init: {"theme": "base", "themeVariables": {"primaryColor": "hsl(60,100%,50%)"}}}%%
flowchart TD
A''',
    );
    expect(
      flattenScene(
        themed.nodes,
      ).whereType<SceneShape>().map((shape) => shape.fill?.color),
      contains(const Color(0xffffff00)),
    );
  });
}
