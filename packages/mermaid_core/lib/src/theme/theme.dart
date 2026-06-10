/// Mermaid theme variables (subset relevant to currently supported diagrams),
/// with defaults matching upstream theme-default.js.
library;

import '../color.dart';

class MermaidTheme {
  const MermaidTheme({
    required this.background,
    required this.primaryColor,
    required this.primaryTextColor,
    required this.primaryBorderColor,
    required this.secondaryColor,
    required this.lineColor,
    required this.arrowheadColor,
    required this.textColor,
    required this.nodeBorder,
    required this.mainBkg,
    required this.clusterBkg,
    required this.clusterBorder,
    required this.titleColor,
    required this.edgeLabelBackground,
    required this.fontFamily,
    required this.fontSize,
  });

  final Color background;
  final Color primaryColor;
  final Color primaryTextColor;
  final Color primaryBorderColor;
  final Color secondaryColor;
  final Color lineColor;
  final Color arrowheadColor;
  final Color textColor;
  final Color nodeBorder;
  final Color mainBkg;
  final Color clusterBkg;
  final Color clusterBorder;
  final Color titleColor;
  final Color edgeLabelBackground;
  final String fontFamily;
  final double fontSize;

  MermaidTheme copyWith({
    Color? background,
    Color? primaryColor,
    Color? primaryTextColor,
    Color? primaryBorderColor,
    Color? secondaryColor,
    Color? lineColor,
    Color? arrowheadColor,
    Color? textColor,
    Color? nodeBorder,
    Color? mainBkg,
    Color? clusterBkg,
    Color? clusterBorder,
    Color? titleColor,
    Color? edgeLabelBackground,
    String? fontFamily,
    double? fontSize,
  }) =>
      MermaidTheme(
        background: background ?? this.background,
        primaryColor: primaryColor ?? this.primaryColor,
        primaryTextColor: primaryTextColor ?? this.primaryTextColor,
        primaryBorderColor: primaryBorderColor ?? this.primaryBorderColor,
        secondaryColor: secondaryColor ?? this.secondaryColor,
        lineColor: lineColor ?? this.lineColor,
        arrowheadColor: arrowheadColor ?? this.arrowheadColor,
        textColor: textColor ?? this.textColor,
        nodeBorder: nodeBorder ?? this.nodeBorder,
        mainBkg: mainBkg ?? this.mainBkg,
        clusterBkg: clusterBkg ?? this.clusterBkg,
        clusterBorder: clusterBorder ?? this.clusterBorder,
        titleColor: titleColor ?? this.titleColor,
        edgeLabelBackground: edgeLabelBackground ?? this.edgeLabelBackground,
        fontFamily: fontFamily ?? this.fontFamily,
        fontSize: fontSize ?? this.fontSize,
      );

  @override
  bool operator ==(Object other) =>
      other is MermaidTheme &&
      other.background == background &&
      other.primaryColor == primaryColor &&
      other.primaryTextColor == primaryTextColor &&
      other.primaryBorderColor == primaryBorderColor &&
      other.secondaryColor == secondaryColor &&
      other.lineColor == lineColor &&
      other.arrowheadColor == arrowheadColor &&
      other.textColor == textColor &&
      other.nodeBorder == nodeBorder &&
      other.mainBkg == mainBkg &&
      other.clusterBkg == clusterBkg &&
      other.clusterBorder == clusterBorder &&
      other.titleColor == titleColor &&
      other.edgeLabelBackground == edgeLabelBackground &&
      other.fontFamily == fontFamily &&
      other.fontSize == fontSize;

  @override
  int get hashCode => Object.hash(
        background,
        primaryColor,
        primaryTextColor,
        primaryBorderColor,
        secondaryColor,
        lineColor,
        arrowheadColor,
        textColor,
        nodeBorder,
        mainBkg,
        clusterBkg,
        clusterBorder,
        titleColor,
        edgeLabelBackground,
        fontFamily,
        fontSize,
      );

  /// Values from upstream theme-default.js.
  static const MermaidTheme defaultTheme = MermaidTheme(
    background: Color(0xffffffff),
    primaryColor: Color(0xffececff),
    primaryTextColor: Color(0xff131300),
    primaryBorderColor: Color(0xff9370db),
    secondaryColor: Color(0xffffffde),
    lineColor: Color(0xff333333),
    arrowheadColor: Color(0xff333333),
    textColor: Color(0xff333333),
    nodeBorder: Color(0xff9370db),
    mainBkg: Color(0xffececff),
    clusterBkg: Color(0xffffffde),
    clusterBorder: Color(0xffaaaa33),
    titleColor: Color(0xff333333),
    edgeLabelBackground: Color(0xcce8e8e8),
    fontFamily: '"trebuchet ms", verdana, arial, sans-serif',
    fontSize: 16,
  );

  /// Values from upstream theme-dark.js (approximate core subset). Like
  /// upstream, the dark theme paints no background of its own.
  static const MermaidTheme darkTheme = MermaidTheme(
    background: Color(0x00000000),
    primaryColor: Color(0xff1f2020),
    primaryTextColor: Color(0xffe0dfdf),
    primaryBorderColor: Color(0xff81b1db),
    secondaryColor: Color(0xff182028),
    lineColor: Color(0xffd3d3d3),
    arrowheadColor: Color(0xffd3d3d3),
    textColor: Color(0xffcccccc),
    nodeBorder: Color(0xff81b1db),
    mainBkg: Color(0xff1f2020),
    clusterBkg: Color(0xff182028),
    clusterBorder: Color(0xff7c0000),
    titleColor: Color(0xfff9fffe),
    edgeLabelBackground: Color(0xff5a5a5a),
    fontFamily: '"trebuchet ms", verdana, arial, sans-serif',
    fontSize: 16,
  );

  /// Values from upstream theme-forest.js.
  static const MermaidTheme forestTheme = MermaidTheme(
    background: Color(0xffffffff),
    primaryColor: Color(0xffcde498),
    primaryTextColor: Color(0xff333333),
    primaryBorderColor: Color(0xff13540c),
    secondaryColor: Color(0xffcdffb2),
    lineColor: Color(0xff008000),
    arrowheadColor: Color(0xff008000),
    textColor: Color(0xff333333),
    nodeBorder: Color(0xff13540c),
    mainBkg: Color(0xffcde498),
    clusterBkg: Color(0xffcdffb2),
    clusterBorder: Color(0xff6eaa49),
    titleColor: Color(0xff333333),
    edgeLabelBackground: Color(0xcce8e8e8),
    fontFamily: '"trebuchet ms", verdana, arial, sans-serif',
    fontSize: 16,
  );

  /// Values from upstream theme-neutral.js.
  static const MermaidTheme neutralTheme = MermaidTheme(
    background: Color(0xffffffff),
    primaryColor: Color(0xffeeeeee),
    primaryTextColor: Color(0xff333333),
    primaryBorderColor: Color(0xff999999),
    secondaryColor: Color(0xfff4f4f4),
    lineColor: Color(0xff666666),
    arrowheadColor: Color(0xff333333),
    textColor: Color(0xff333333),
    nodeBorder: Color(0xff999999),
    mainBkg: Color(0xffeeeeee),
    clusterBkg: Color(0xfff6f6f6),
    clusterBorder: Color(0xffaaaaaa),
    titleColor: Color(0xff333333),
    edgeLabelBackground: Color(0xccffffff),
    fontFamily: '"trebuchet ms", verdana, arial, sans-serif',
    fontSize: 16,
  );

  /// Theme by its mermaid name; unknown names return [defaultTheme].
  static MermaidTheme named(String name) => switch (name) {
        'dark' => darkTheme,
        'forest' => forestTheme,
        'neutral' => neutralTheme,
        _ => defaultTheme,
      };
}
