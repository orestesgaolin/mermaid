/// Mermaid theme variables (subset relevant to currently supported diagrams),
/// with defaults matching upstream theme-default.js.
library;

import '../color.dart';

/// xychart `plotColorPalette` for the default/forest/neutral themes
/// (upstream theme-default.js `#ECECFF,#8493A6,…`).
const _defaultXyChartPlotColorPalette = <Color>[
  Color(0xffececff), Color(0xff8493a6), Color(0xffffc3a0), Color(0xffdcdde1),
  Color(0xffb8e994), Color(0xffd1a36f), Color(0xffc3cde6), Color(0xffffb6c1),
  Color(0xff496078), Color(0xfff8f3e3),
];

/// xychart `plotColorPalette` for the dark theme (upstream theme-dark.js).
const _darkXyChartPlotColorPalette = <Color>[
  Color(0xff3498db), Color(0xff2ecc71), Color(0xffe74c3c), Color(0xfff1c40f),
  Color(0xffbdc3c7), Color(0xffffffff), Color(0xff34495e), Color(0xff9b59b6),
  Color(0xff1abc9c), Color(0xffe67e22),
];

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
    this.cScale0 = const Color(0xffb9b9ff),
    this.cScale1 = const Color(0xffffffab),
    this.cScale2 = const Color(0xffe9ffb9),
    this.cScale3 = const Color(0xffdeb9ff),
    this.cScale4 = const Color(0xffffb9ff),
    this.cScale5 = const Color(0xffffb9de),
    this.cScale6 = const Color(0xffffb9b9),
    this.cScale7 = const Color(0xffffdeb9),
    this.cScale8 = const Color(0xffdeffb9),
    this.cScale9 = const Color(0xffb9ffde),
    this.cScale10 = const Color(0xffb9ffff),
    this.cScale11 = const Color(0xffb9deff),
    this.cScaleInv0 = const Color(0xffffffb9),
    this.cScaleInv1 = const Color(0xffababff),
    this.cScaleInv2 = const Color(0xffcfb9ff),
    this.cScaleInv3 = const Color(0xffdaffb9),
    this.cScaleInv4 = const Color(0xffb9ffb9),
    this.cScaleInv5 = const Color(0xffb9ffda),
    this.cScaleInv6 = const Color(0xffb9ffff),
    this.cScaleInv7 = const Color(0xffb9daff),
    this.cScaleInv8 = const Color(0xffdab9ff),
    this.cScaleInv9 = const Color(0xffffb9da),
    this.cScaleInv10 = const Color(0xffffb9b9),
    this.cScaleInv11 = const Color(0xffffdab9),
    this.cScaleLabel0 = const Color(0xffffffff),
    this.cScaleLabel1 = const Color(0xff000000),
    this.cScaleLabel2 = const Color(0xff000000),
    this.cScaleLabel3 = const Color(0xffffffff),
    this.cScaleLabel4 = const Color(0xff000000),
    this.cScaleLabel5 = const Color(0xff000000),
    this.cScaleLabel6 = const Color(0xff000000),
    this.cScaleLabel7 = const Color(0xff000000),
    this.cScaleLabel8 = const Color(0xff000000),
    this.cScaleLabel9 = const Color(0xff000000),
    this.cScaleLabel10 = const Color(0xff000000),
    this.cScaleLabel11 = const Color(0xff000000),
    this.cScalePeer0 = const Color(0xff3a3aff),
    this.cScalePeer1 = const Color(0xfff7f800),
    this.cScalePeer2 = const Color(0xffb9ff20),
    this.cScalePeer3 = const Color(0xffa23aff),
    this.cScalePeer4 = const Color(0xffff3aff),
    this.cScalePeer5 = const Color(0xffff3aa2),
    this.cScalePeer6 = const Color(0xffff3a3a),
    this.cScalePeer7 = const Color(0xffffa23a),
    this.cScalePeer8 = const Color(0xff9cff39),
    this.cScalePeer9 = const Color(0xff39ff9c),
    this.cScalePeer10 = const Color(0xff39ffff),
    this.cScalePeer11 = const Color(0xff399cff),
    this.pie1 = const Color(0xffececff),
    this.pie2 = const Color(0xffffffde),
    this.pie3 = const Color(0xffb9ff20),
    this.pie4 = const Color(0xffb9b9ff),
    this.pie5 = const Color(0xffffff45),
    this.pie6 = const Color(0xffd9ff86),
    this.pie7 = const Color(0xffff86ff),
    this.pie8 = const Color(0xff20ffff),
    this.pie9 = const Color(0xffff2020),
    this.pie10 = const Color(0xffff20ff),
    this.pie11 = const Color(0xff20ff90),
    this.pie12 = const Color(0xffff5353),
    this.pieStrokeColor = const Color(0xff000000),
    this.pieOuterStrokeColor = const Color(0xff000000),
    this.pieSectionTextColor = const Color(0xff333333),
    this.pieLegendTextColor = const Color(0xff000000),
    this.pieTitleTextColor = const Color(0xff000000),
    this.git0 = const Color(0xff6c6cff),
    this.git1 = const Color(0xffffff5e),
    this.git2 = const Color(0xffceff6c),
    this.git3 = const Color(0xff6cb6ff),
    this.git4 = const Color(0xff6cffff),
    this.git5 = const Color(0xff6cffb6),
    this.git6 = const Color(0xffff6cff),
    this.git7 = const Color(0xffff6c6c),
    this.gitInv0 = const Color(0xff131300),
    this.gitInv1 = const Color(0xff0000a1),
    this.gitInv2 = const Color(0xff310093),
    this.gitInv3 = const Color(0xff934900),
    this.gitInv4 = const Color(0xff930000),
    this.gitInv5 = const Color(0xff930049),
    this.gitInv6 = const Color(0xff009300),
    this.gitInv7 = const Color(0xff009393),
    this.gitBranchLabel0 = const Color(0xffffffff),
    this.gitBranchLabel1 = const Color(0xff000000),
    this.gitBranchLabel2 = const Color(0xff000000),
    this.gitBranchLabel3 = const Color(0xffffffff),
    this.gitBranchLabel4 = const Color(0xff000000),
    this.gitBranchLabel5 = const Color(0xff000000),
    this.gitBranchLabel6 = const Color(0xff000000),
    this.gitBranchLabel7 = const Color(0xff000000),
    this.commitLabelColor = const Color(0xff000021),
    this.commitLabelBackground = const Color(0xffffffde),
    this.tagLabelColor = const Color(0xff131300),
    this.tagLabelBackground = const Color(0xffececff),
    this.tagLabelBorder = const Color(0xffc7c7f1),
    this.actorBkg = const Color(0xffececff),
    this.actorBorder = const Color(0xff9370db),
    this.actorTextColor = const Color(0xff000000),
    this.actorLineColor = const Color(0xff9370db),
    this.signalColor = const Color(0xff333333),
    this.signalTextColor = const Color(0xff333333),
    this.labelBoxBkgColor = const Color(0xffececff),
    this.labelBoxBorderColor = const Color(0xff9370db),
    this.labelTextColor = const Color(0xff000000),
    this.loopTextColor = const Color(0xff000000),
    this.noteBkgColor = const Color(0xfffff5ad),
    this.noteBorderColor = const Color(0xffaaaa33),
    this.noteTextColor = const Color(0xff000000),
    this.activationBkgColor = const Color(0xfff4f4f4),
    this.activationBorderColor = const Color(0xff666666),
    this.fillType0 = const Color(0xffececff),
    this.fillType1 = const Color(0xffffffde),
    this.fillType2 = const Color(0xffffecfe),
    this.fillType3 = const Color(0xffdeffe0),
    this.fillType4 = const Color(0xffecfffe),
    this.fillType5 = const Color(0xffffdee0),
    this.fillType6 = const Color(0xffffefec),
    this.fillType7 = const Color(0xffdefbff),
    this.quadrant1Fill = const Color(0xffececff),
    this.quadrant2Fill = const Color(0xfff1f1ff),
    this.quadrant3Fill = const Color(0xfff6f6ff),
    this.quadrant4Fill = const Color(0xfffbfbff),
    this.quadrant1TextFill = const Color(0xff131300),
    this.quadrant2TextFill = const Color(0xff0e0e00),
    this.quadrant3TextFill = const Color(0xff090900),
    this.quadrant4TextFill = const Color(0xff040400),
    this.quadrantPointFill = const Color(0xffb9b9ff),
    this.quadrantPointTextFill = const Color(0xff131300),
    this.quadrantXAxisTextFill = const Color(0xff131300),
    this.quadrantYAxisTextFill = const Color(0xff131300),
    this.quadrantInternalBorderStrokeFill = const Color(0xffc7c7f1),
    this.quadrantExternalBorderStrokeFill = const Color(0xffc7c7f1),
    this.quadrantTitleFill = const Color(0xff131300),
    this.attributeBackgroundColorOdd = const Color(0xffffffff),
    this.attributeBackgroundColorEven = const Color(0xfff2f2f2),
    this.rowOdd = const Color(0xffffffff),
    this.rowEven = const Color(0xfff1f1ff),
    this.venn1 = const Color(0xff5353ff),
    this.venn2 = const Color(0xffffff45),
    this.venn3 = const Color(0xffb9ff20),
    this.venn4 = const Color(0xffff53ff),
    this.venn5 = const Color(0xff53ffff),
    this.venn6 = const Color(0xff45ff45),
    this.venn7 = const Color(0xffff5353),
    this.venn8 = const Color(0xff45ffff),
    this.vennTitleTextColor = const Color(0xff333333),
    this.vennSetTextColor = const Color(0xff333333),
    this.requirementBackground = const Color(0xffececff),
    this.requirementBorderColor = const Color(0xffc7c7f1),
    this.requirementTextColor = const Color(0xff131300),
    this.relationColor = const Color(0xff333333),
    this.relationLabelBackground = const Color(0xcce8e8e8),
    this.relationLabelColor = const Color(0xff000000),
    this.xyChartPlotColorPalette = _defaultXyChartPlotColorPalette,
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

  /// General ordinal color scale (mindmap, treemap, radar, timeline, etc.).
  final Color cScale0;
  final Color cScale1;
  final Color cScale2;
  final Color cScale3;
  final Color cScale4;
  final Color cScale5;
  final Color cScale6;
  final Color cScale7;
  final Color cScale8;
  final Color cScale9;
  final Color cScale10;
  final Color cScale11;
  final Color cScaleInv0;
  final Color cScaleInv1;
  final Color cScaleInv2;
  final Color cScaleInv3;
  final Color cScaleInv4;
  final Color cScaleInv5;
  final Color cScaleInv6;
  final Color cScaleInv7;
  final Color cScaleInv8;
  final Color cScaleInv9;
  final Color cScaleInv10;
  final Color cScaleInv11;
  final Color cScaleLabel0;
  final Color cScaleLabel1;
  final Color cScaleLabel2;
  final Color cScaleLabel3;
  final Color cScaleLabel4;
  final Color cScaleLabel5;
  final Color cScaleLabel6;
  final Color cScaleLabel7;
  final Color cScaleLabel8;
  final Color cScaleLabel9;
  final Color cScaleLabel10;
  final Color cScaleLabel11;
  final Color cScalePeer0;
  final Color cScalePeer1;
  final Color cScalePeer2;
  final Color cScalePeer3;
  final Color cScalePeer4;
  final Color cScalePeer5;
  final Color cScalePeer6;
  final Color cScalePeer7;
  final Color cScalePeer8;
  final Color cScalePeer9;
  final Color cScalePeer10;
  final Color cScalePeer11;

  /// Pie chart palette and text/stroke colors.
  final Color pie1;
  final Color pie2;
  final Color pie3;
  final Color pie4;
  final Color pie5;
  final Color pie6;
  final Color pie7;
  final Color pie8;
  final Color pie9;
  final Color pie10;
  final Color pie11;
  final Color pie12;
  final Color pieStrokeColor;
  final Color pieOuterStrokeColor;
  final Color pieSectionTextColor;
  final Color pieLegendTextColor;
  final Color pieTitleTextColor;

  /// Git graph branch/commit/tag colors.
  final Color git0;
  final Color git1;
  final Color git2;
  final Color git3;
  final Color git4;
  final Color git5;
  final Color git6;
  final Color git7;
  final Color gitInv0;
  final Color gitInv1;
  final Color gitInv2;
  final Color gitInv3;
  final Color gitInv4;
  final Color gitInv5;
  final Color gitInv6;
  final Color gitInv7;
  final Color gitBranchLabel0;
  final Color gitBranchLabel1;
  final Color gitBranchLabel2;
  final Color gitBranchLabel3;
  final Color gitBranchLabel4;
  final Color gitBranchLabel5;
  final Color gitBranchLabel6;
  final Color gitBranchLabel7;
  final Color commitLabelColor;
  final Color commitLabelBackground;
  final Color tagLabelColor;
  final Color tagLabelBackground;
  final Color tagLabelBorder;

  /// Sequence diagram actor/signal/note/activation colors.
  final Color actorBkg;
  final Color actorBorder;
  final Color actorTextColor;
  final Color actorLineColor;
  final Color signalColor;
  final Color signalTextColor;
  final Color labelBoxBkgColor;
  final Color labelBoxBorderColor;
  final Color labelTextColor;
  final Color loopTextColor;
  final Color noteBkgColor;
  final Color noteBorderColor;
  final Color noteTextColor;
  final Color activationBkgColor;
  final Color activationBorderColor;

  /// User-journey section fill colors.
  final Color fillType0;
  final Color fillType1;
  final Color fillType2;
  final Color fillType3;
  final Color fillType4;
  final Color fillType5;
  final Color fillType6;
  final Color fillType7;

  /// Quadrant chart fills and axis/point/title text colors.
  final Color quadrant1Fill;
  final Color quadrant2Fill;
  final Color quadrant3Fill;
  final Color quadrant4Fill;
  final Color quadrant1TextFill;
  final Color quadrant2TextFill;
  final Color quadrant3TextFill;
  final Color quadrant4TextFill;
  final Color quadrantPointFill;
  final Color quadrantPointTextFill;
  final Color quadrantXAxisTextFill;
  final Color quadrantYAxisTextFill;
  final Color quadrantInternalBorderStrokeFill;
  final Color quadrantExternalBorderStrokeFill;
  final Color quadrantTitleFill;

  /// Entity-relationship attribute/row background colors.
  final Color attributeBackgroundColorOdd;
  final Color attributeBackgroundColorEven;
  final Color rowOdd;
  final Color rowEven;

  /// Venn diagram set fills and text colors.
  final Color venn1;
  final Color venn2;
  final Color venn3;
  final Color venn4;
  final Color venn5;
  final Color venn6;
  final Color venn7;
  final Color venn8;
  final Color vennTitleTextColor;
  final Color vennSetTextColor;

  /// Requirement diagram fill/border/text and relation colors.
  final Color requirementBackground;
  final Color requirementBorderColor;
  final Color requirementTextColor;
  final Color relationColor;
  final Color relationLabelBackground;
  final Color relationLabelColor;

  /// xychart plot (bar/line) ordinal palette; upstream `xyChart.plotColorPalette`.
  final List<Color> xyChartPlotColorPalette;

  // --- Convenience list views over the indexed palette fields. ---
  List<Color> get cScale => [cScale0, cScale1, cScale2, cScale3, cScale4, cScale5, cScale6, cScale7, cScale8, cScale9, cScale10, cScale11];
  List<Color> get cScaleInv => [cScaleInv0, cScaleInv1, cScaleInv2, cScaleInv3, cScaleInv4, cScaleInv5, cScaleInv6, cScaleInv7, cScaleInv8, cScaleInv9, cScaleInv10, cScaleInv11];
  List<Color> get cScaleLabel => [cScaleLabel0, cScaleLabel1, cScaleLabel2, cScaleLabel3, cScaleLabel4, cScaleLabel5, cScaleLabel6, cScaleLabel7, cScaleLabel8, cScaleLabel9, cScaleLabel10, cScaleLabel11];
  List<Color> get cScalePeer => [cScalePeer0, cScalePeer1, cScalePeer2, cScalePeer3, cScalePeer4, cScalePeer5, cScalePeer6, cScalePeer7, cScalePeer8, cScalePeer9, cScalePeer10, cScalePeer11];
  List<Color> get pie => [pie1, pie2, pie3, pie4, pie5, pie6, pie7, pie8, pie9, pie10, pie11, pie12];
  List<Color> get git => [git0, git1, git2, git3, git4, git5, git6, git7];
  List<Color> get gitInv => [gitInv0, gitInv1, gitInv2, gitInv3, gitInv4, gitInv5, gitInv6, gitInv7];
  List<Color> get gitBranchLabel => [gitBranchLabel0, gitBranchLabel1, gitBranchLabel2, gitBranchLabel3, gitBranchLabel4, gitBranchLabel5, gitBranchLabel6, gitBranchLabel7];
  List<Color> get fillType => [fillType0, fillType1, fillType2, fillType3, fillType4, fillType5, fillType6, fillType7];
  List<Color> get venn => [venn1, venn2, venn3, venn4, venn5, venn6, venn7, venn8];

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
    xyChartPlotColorPalette: _darkXyChartPlotColorPalette,
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
    cScale0: Color(0xff1f2020),
    cScale1: Color(0xff0b0000),
    cScale2: Color(0xff4d1037),
    cScale3: Color(0xff3f5258),
    cScale4: Color(0xff4f2f1b),
    cScale5: Color(0xff6e0a0a),
    cScale6: Color(0xff3b0048),
    cScale7: Color(0xff995a01),
    cScale8: Color(0xff154706),
    cScale9: Color(0xff161722),
    cScale10: Color(0xff00296f),
    cScale11: Color(0xff01629c),
    cScaleInv0: Color(0xffe0dfdf),
    cScaleInv1: Color(0xfff4ffff),
    cScaleInv2: Color(0xffb2efc8),
    cScaleInv3: Color(0xffc0ada7),
    cScaleInv4: Color(0xffb0d0e4),
    cScaleInv5: Color(0xff91f5f5),
    cScaleInv6: Color(0xffc4ffb7),
    cScaleInv7: Color(0xff66a5fe),
    cScaleInv8: Color(0xffeab8f9),
    cScaleInv9: Color(0xffe9e8dd),
    cScaleInv10: Color(0xffffd690),
    cScaleInv11: Color(0xfffe9d63),
    cScaleLabel0: Color(0xffd3d3d3),
    cScaleLabel1: Color(0xffd3d3d3),
    cScaleLabel2: Color(0xffd3d3d3),
    cScaleLabel3: Color(0xffd3d3d3),
    cScaleLabel4: Color(0xffd3d3d3),
    cScaleLabel5: Color(0xffd3d3d3),
    cScaleLabel6: Color(0xffd3d3d3),
    cScaleLabel7: Color(0xffd3d3d3),
    cScaleLabel8: Color(0xffd3d3d3),
    cScaleLabel9: Color(0xffd3d3d3),
    cScaleLabel10: Color(0xffd3d3d3),
    cScaleLabel11: Color(0xffd3d3d3),
    cScalePeer0: Color(0xff383a3a),
    cScalePeer1: Color(0xff3e0000),
    cScalePeer2: Color(0xff771955),
    cScalePeer3: Color(0xff546e76),
    cScalePeer4: Color(0xff754628),
    cScalePeer5: Color(0xff9d0e0e),
    cScalePeer6: Color(0xff65007b),
    cScalePeer7: Color(0xffcc7801),
    cScalePeer8: Color(0xff23760a),
    cScalePeer9: Color(0xff2a2c41),
    cScalePeer10: Color(0xff003ca2),
    cScalePeer11: Color(0xff0182cf),
    pie1: Color(0xff0b0000),
    pie2: Color(0xff4d1037),
    pie3: Color(0xff3f5258),
    pie4: Color(0xff4f2f1b),
    pie5: Color(0xff6e0a0a),
    pie6: Color(0xff3b0048),
    pie7: Color(0xff995a01),
    pie8: Color(0xff154706),
    pie9: Color(0xff161722),
    pie10: Color(0xff00296f),
    pie11: Color(0xff01629c),
    pie12: Color(0xff1f2020),
    pieStrokeColor: Color(0xff000000),
    pieOuterStrokeColor: Color(0xff000000),
    pieSectionTextColor: Color(0xffcccccc),
    pieLegendTextColor: Color(0xffd3d3d3),
    pieTitleTextColor: Color(0xffd3d3d3),
    git0: Color(0xff797d7d),
    git1: Color(0xffa12273),
    git2: Color(0xff6a8993),
    git3: Color(0xff9b5c35),
    git4: Color(0xffcb1313),
    git5: Color(0xff65007b),
    git6: Color(0xffcc7801),
    git7: Color(0xff31a50e),
    gitInv0: Color(0xff868282),
    gitInv1: Color(0xff5edd8c),
    gitInv2: Color(0xff95766c),
    gitInv3: Color(0xff64a3ca),
    gitInv4: Color(0xff34eded),
    gitInv5: Color(0xff9aff84),
    gitInv6: Color(0xff3387fe),
    gitInv7: Color(0xffce5af1),
    gitBranchLabel0: Color(0xff2c2c2c),
    gitBranchLabel1: Color(0xffd3d3d3),
    gitBranchLabel2: Color(0xffd3d3d3),
    gitBranchLabel3: Color(0xff2c2c2c),
    gitBranchLabel4: Color(0xffd3d3d3),
    gitBranchLabel5: Color(0xffd3d3d3),
    gitBranchLabel6: Color(0xffd3d3d3),
    gitBranchLabel7: Color(0xffd3d3d3),
    commitLabelColor: Color(0xffb8b6b6),
    commitLabelBackground: Color(0xff474949),
    tagLabelColor: Color(0xffe0dfdf),
    tagLabelBackground: Color(0xff1f2020),
    tagLabelBorder: Color(0xffcccccc),
    actorBkg: Color(0xff1f2020),
    actorBorder: Color(0xffcccccc),
    actorTextColor: Color(0xffd3d3d3),
    actorLineColor: Color(0xffcccccc),
    signalColor: Color(0xffd3d3d3),
    signalTextColor: Color(0xffd3d3d3),
    labelBoxBkgColor: Color(0xff1f2020),
    labelBoxBorderColor: Color(0xffcccccc),
    labelTextColor: Color(0xffd3d3d3),
    loopTextColor: Color(0xffd3d3d3),
    noteBkgColor: Color(0xff474949),
    noteBorderColor: Color(0xff2f2f2f),
    noteTextColor: Color(0xffb8b6b6),
    activationBkgColor: Color(0xff474949),
    activationBorderColor: Color(0xffcccccc),
    fillType0: Color(0xff1f2020),
    fillType1: Color(0xff474949),
    fillType2: Color(0xff1f1f20),
    fillType3: Color(0xff474749),
    fillType4: Color(0xff1f201f),
    fillType5: Color(0xff474947),
    fillType6: Color(0xff201f20),
    fillType7: Color(0xff494749),
    quadrant1Fill: Color(0xff1f2020),
    quadrant2Fill: Color(0xff242525),
    quadrant3Fill: Color(0xff292a2a),
    quadrant4Fill: Color(0xff2e2f2f),
    quadrant1TextFill: Color(0xffe0dfdf),
    quadrant2TextFill: Color(0xffdbdada),
    quadrant3TextFill: Color(0xffd6d5d5),
    quadrant4TextFill: Color(0xffd1d0d0),
    quadrantPointFill: Color(0xff383a3a),
    quadrantPointTextFill: Color(0xffe0dfdf),
    quadrantXAxisTextFill: Color(0xffe0dfdf),
    quadrantYAxisTextFill: Color(0xffe0dfdf),
    quadrantInternalBorderStrokeFill: Color(0xffcccccc),
    quadrantExternalBorderStrokeFill: Color(0xffcccccc),
    quadrantTitleFill: Color(0xffe0dfdf),
    attributeBackgroundColorOdd: Color(0xff525252),
    attributeBackgroundColorEven: Color(0xff383838),
    rowOdd: Color(0xff2c2d2d),
    rowEven: Color(0xff060606),
    venn1: Color(0xff6a6e6e),
    venn2: Color(0xffa40000),
    venn3: Color(0xffcc2a91),
    venn4: Color(0xff87a1a9),
    venn5: Color(0xffbf7344),
    venn6: Color(0xffeb2626),
    venn7: Color(0xffb800e1),
    venn8: Color(0xfffeab35),
    vennTitleTextColor: Color(0xfff9fffe),
    vennSetTextColor: Color(0xffcccccc),
    requirementBackground: Color(0xff1f2020),
    requirementBorderColor: Color(0xffcccccc),
    requirementTextColor: Color(0xffe0dfdf),
    relationColor: Color(0xffd3d3d3),
    relationLabelBackground: Color(0xff474949),
    relationLabelColor: Color(0xffd3d3d3),
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
    cScale0: Color(0xffb9d970),
    cScale1: Color(0xffacff7f),
    cScale2: Color(0xffcde498),
    cScale3: Color(0xff84d970),
    cScale4: Color(0xff70d990),
    cScale5: Color(0xff70d9c5),
    cScale6: Color(0xff70b9d9),
    cScale7: Color(0xff7084d9),
    cScale8: Color(0xffc570d9),
    cScale9: Color(0xffd97084),
    cScale10: Color(0xffd99070),
    cScale11: Color(0xffd9c570),
    cScaleInv0: Color(0xff9070d9),
    cScaleInv1: Color(0xffd27fff),
    cScaleInv2: Color(0xffaf98e4),
    cScaleInv3: Color(0xffc570d9),
    cScaleInv4: Color(0xffd970b9),
    cScaleInv5: Color(0xffd97084),
    cScaleInv6: Color(0xffd99070),
    cScaleInv7: Color(0xffd9c570),
    cScaleInv8: Color(0xff84d970),
    cScaleInv9: Color(0xff70d9c5),
    cScaleInv10: Color(0xff70b9d9),
    cScaleInv11: Color(0xff7084d9),
    cScaleLabel0: Color(0xff000000),
    cScaleLabel1: Color(0xff000000),
    cScaleLabel2: Color(0xff000000),
    cScaleLabel3: Color(0xff000000),
    cScaleLabel4: Color(0xff000000),
    cScaleLabel5: Color(0xff000000),
    cScaleLabel6: Color(0xff000000),
    cScaleLabel7: Color(0xff000000),
    cScaleLabel8: Color(0xff000000),
    cScaleLabel9: Color(0xff000000),
    cScaleLabel10: Color(0xff000000),
    cScaleLabel11: Color(0xff000000),
    cScalePeer0: Color(0xff7ca02a),
    cScalePeer1: Color(0xff47cb00),
    cScalePeer2: Color(0xff8cb42f),
    cScalePeer3: Color(0xff41a02a),
    cScalePeer4: Color(0xff2aa04d),
    cScalePeer5: Color(0xff2aa088),
    cScalePeer6: Color(0xff2a7ca0),
    cScalePeer7: Color(0xff2a41a0),
    cScalePeer8: Color(0xff882aa0),
    cScalePeer9: Color(0xffa02a41),
    cScalePeer10: Color(0xffa04d2a),
    cScalePeer11: Color(0xffa0882a),
    pie1: Color(0xffcde498),
    pie2: Color(0xffcdffb2),
    pie3: Color(0xffe1efc0),
    pie4: Color(0xff8cb42f),
    pie5: Color(0xff6aff19),
    pie6: Color(0xff33b42f),
    pie7: Color(0xff70d990),
    pie8: Color(0xffd99070),
    pie9: Color(0xff98cde4),
    pie10: Color(0xff1a6330),
    pie11: Color(0xff63301a),
    pie12: Color(0xff1a4d63),
    pieStrokeColor: Color(0xff000000),
    pieOuterStrokeColor: Color(0xff000000),
    pieSectionTextColor: Color(0xff000000),
    pieLegendTextColor: Color(0xff000000),
    pieTitleTextColor: Color(0xff000000),
    git0: Color(0xff9bc834),
    git1: Color(0xff7aff32),
    git2: Color(0xffb0d45b),
    git3: Color(0xffc8ab34),
    git4: Color(0xffc86134),
    git5: Color(0xffc83452),
    git6: Color(0xff34c861),
    git7: Color(0xff349bc8),
    gitInv0: Color(0xff6437cb),
    gitInv1: Color(0xff8500cd),
    gitInv2: Color(0xff4f2ba4),
    gitInv3: Color(0xff3754cb),
    gitInv4: Color(0xff379ecb),
    gitInv5: Color(0xff37cbad),
    gitInv6: Color(0xffcb379e),
    gitInv7: Color(0xffcb6437),
    gitBranchLabel0: Color(0xffffffff),
    gitBranchLabel1: Color(0xff000000),
    gitBranchLabel2: Color(0xff000000),
    gitBranchLabel3: Color(0xffffffff),
    gitBranchLabel4: Color(0xff000000),
    gitBranchLabel5: Color(0xff000000),
    gitBranchLabel6: Color(0xff000000),
    gitBranchLabel7: Color(0xff000000),
    commitLabelColor: Color(0xff32004d),
    commitLabelBackground: Color(0xffcdffb2),
    tagLabelColor: Color(0xff321b67),
    tagLabelBackground: Color(0xffcde498),
    tagLabelBorder: Color(0xffabb594),
    actorBkg: Color(0xffcde498),
    actorBorder: Color(0xffa6cf47),
    actorTextColor: Color(0xff000000),
    actorLineColor: Color(0xffa6cf47),
    signalColor: Color(0xff333333),
    signalTextColor: Color(0xff333333),
    labelBoxBkgColor: Color(0xffcde498),
    labelBoxBorderColor: Color(0xff326932),
    labelTextColor: Color(0xff000000),
    loopTextColor: Color(0xff000000),
    noteBkgColor: Color(0xfffff5ad),
    noteBorderColor: Color(0xff6eaa49),
    noteTextColor: Color(0xff000000),
    activationBkgColor: Color(0xfff4f4f4),
    activationBorderColor: Color(0xff666666),
    fillType0: Color(0xffcde498),
    fillType1: Color(0xffcdffb2),
    fillType2: Color(0xff98e4b4),
    fillType3: Color(0xffb2ffe9),
    fillType4: Color(0xffe4aa98),
    fillType5: Color(0xffffdfb2),
    fillType6: Color(0xff98c3e4),
    fillType7: Color(0xffb2c3ff),
    quadrant1Fill: Color(0xffcde498),
    quadrant2Fill: Color(0xffd2e99d),
    quadrant3Fill: Color(0xffd7eea2),
    quadrant4Fill: Color(0xffdcf3a7),
    quadrant1TextFill: Color(0xff321b67),
    quadrant2TextFill: Color(0xff2d1662),
    quadrant3TextFill: Color(0xff28115d),
    quadrant4TextFill: Color(0xff230c58),
    quadrantPointFill: Color(0xffb9d970),
    quadrantPointTextFill: Color(0xff321b67),
    quadrantXAxisTextFill: Color(0xff321b67),
    quadrantYAxisTextFill: Color(0xff321b67),
    quadrantInternalBorderStrokeFill: Color(0xffabb594),
    quadrantExternalBorderStrokeFill: Color(0xffabb594),
    quadrantTitleFill: Color(0xff321b67),
    attributeBackgroundColorOdd: Color(0xffffffff),
    attributeBackgroundColorEven: Color(0xfff2f2f2),
    rowOdd: Color(0xffffffff),
    rowEven: Color(0xfff4f9e9),
    venn1: Color(0xff8cb42f),
    venn2: Color(0xff6aff19),
    venn3: Color(0xffa6cf47),
    venn4: Color(0xff2fb457),
    venn5: Color(0xffb4572f),
    venn6: Color(0xff19ffae),
    venn7: Color(0xff2f8cb4),
    venn8: Color(0xff196aff),
    vennTitleTextColor: Color(0xff333333),
    vennSetTextColor: Color(0xff000000),
    requirementBackground: Color(0xffcde498),
    requirementBorderColor: Color(0xffabb594),
    requirementTextColor: Color(0xff321b67),
    relationColor: Color(0xff000000),
    relationLabelBackground: Color(0xffe8e8e8),
    relationLabelColor: Color(0xff000000),
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
    cScale0: Color(0xff555555),
    cScale1: Color(0xfff4f4f4),
    cScale2: Color(0xff555555),
    cScale3: Color(0xffbbbbbb),
    cScale4: Color(0xff777777),
    cScale5: Color(0xff999999),
    cScale6: Color(0xffdddddd),
    cScale7: Color(0xffffffff),
    cScale8: Color(0xffdddddd),
    cScale9: Color(0xffbbbbbb),
    cScale10: Color(0xff999999),
    cScale11: Color(0xff777777),
    cScaleInv0: Color(0xffaaaaaa),
    cScaleInv1: Color(0xff0b0b0b),
    cScaleInv2: Color(0xffaaaaaa),
    cScaleInv3: Color(0xff444444),
    cScaleInv4: Color(0xff888888),
    cScaleInv5: Color(0xff666666),
    cScaleInv6: Color(0xff222222),
    cScaleInv7: Color(0xff000000),
    cScaleInv8: Color(0xff222222),
    cScaleInv9: Color(0xff444444),
    cScaleInv10: Color(0xff666666),
    cScaleInv11: Color(0xff888888),
    cScaleLabel0: Color(0xfff4f4f4),
    cScaleLabel1: Color(0xff333333),
    cScaleLabel2: Color(0xfff4f4f4),
    cScaleLabel3: Color(0xff333333),
    cScaleLabel4: Color(0xff333333),
    cScaleLabel5: Color(0xff333333),
    cScaleLabel6: Color(0xff333333),
    cScaleLabel7: Color(0xff333333),
    cScaleLabel8: Color(0xff333333),
    cScaleLabel9: Color(0xff333333),
    cScaleLabel10: Color(0xff333333),
    cScaleLabel11: Color(0xff333333),
    cScalePeer0: Color(0xff3b3b3b),
    cScalePeer1: Color(0xffdadada),
    cScalePeer2: Color(0xff3b3b3b),
    cScalePeer3: Color(0xffa1a1a1),
    cScalePeer4: Color(0xff5e5e5e),
    cScalePeer5: Color(0xff7f7f7f),
    cScalePeer6: Color(0xffc4c4c4),
    cScalePeer7: Color(0xffe5e5e5),
    cScalePeer8: Color(0xffc4c4c4),
    cScalePeer9: Color(0xffa1a1a1),
    cScalePeer10: Color(0xff7f7f7f),
    cScalePeer11: Color(0xff5e5e5e),
    pie1: Color(0xfff4f4f4),
    pie2: Color(0xff555555),
    pie3: Color(0xffbbbbbb),
    pie4: Color(0xff777777),
    pie5: Color(0xff999999),
    pie6: Color(0xffdddddd),
    pie7: Color(0xffffffff),
    pie8: Color(0xffdddddd),
    pie9: Color(0xffbbbbbb),
    pie10: Color(0xff999999),
    pie11: Color(0xff777777),
    pie12: Color(0xff555555),
    pieStrokeColor: Color(0xff000000),
    pieOuterStrokeColor: Color(0xff000000),
    pieSectionTextColor: Color(0xff000000),
    pieLegendTextColor: Color(0xff333333),
    pieTitleTextColor: Color(0xff333333),
    git0: Color(0xffb4b4b4),
    git1: Color(0xff555555),
    git2: Color(0xffbbbbbb),
    git3: Color(0xff777777),
    git4: Color(0xff999999),
    git5: Color(0xffdddddd),
    git6: Color(0xffffffff),
    git7: Color(0xffdddddd),
    gitInv0: Color(0xff4b4b4b),
    gitInv1: Color(0xffaaaaaa),
    gitInv2: Color(0xff444444),
    gitInv3: Color(0xff888888),
    gitInv4: Color(0xff666666),
    gitInv5: Color(0xff222222),
    gitInv6: Color(0xff000000),
    gitInv7: Color(0xff222222),
    gitBranchLabel0: Color(0xff333333),
    gitBranchLabel1: Color(0xffffffff),
    gitBranchLabel2: Color(0xff333333),
    gitBranchLabel3: Color(0xffffffff),
    gitBranchLabel4: Color(0xff333333),
    gitBranchLabel5: Color(0xff333333),
    gitBranchLabel6: Color(0xff333333),
    gitBranchLabel7: Color(0xff333333),
    commitLabelColor: Color(0xff030303),
    commitLabelBackground: Color(0xfffcfcfc),
    tagLabelColor: Color(0xff111111),
    tagLabelBackground: Color(0xffeeeeee),
    tagLabelBorder: Color(0xffd4d4d4),
    actorBkg: Color(0xffeeeeee),
    actorBorder: Color(0xffd4d4d4),
    actorTextColor: Color(0xff333333),
    actorLineColor: Color(0xffd4d4d4),
    signalColor: Color(0xff333333),
    signalTextColor: Color(0xff333333),
    labelBoxBkgColor: Color(0xffeeeeee),
    labelBoxBorderColor: Color(0xffd4d4d4),
    labelTextColor: Color(0xff333333),
    loopTextColor: Color(0xff333333),
    noteBkgColor: Color(0xff666666),
    noteBorderColor: Color(0xff999999),
    noteTextColor: Color(0xffffffff),
    activationBkgColor: Color(0xfff4f4f4),
    activationBorderColor: Color(0xff666666),
    fillType0: Color(0xffeeeeee),
    fillType1: Color(0xfffcfcfc),
    fillType2: Color(0xffeeeeee),
    fillType3: Color(0xfffcfcfc),
    fillType4: Color(0xffeeeeee),
    fillType5: Color(0xfffcfcfc),
    fillType6: Color(0xffeeeeee),
    fillType7: Color(0xfffcfcfc),
    quadrant1Fill: Color(0xffeeeeee),
    quadrant2Fill: Color(0xfff3f3f3),
    quadrant3Fill: Color(0xfff8f8f8),
    quadrant4Fill: Color(0xfffdfdfd),
    quadrant1TextFill: Color(0xff111111),
    quadrant2TextFill: Color(0xff0c0c0c),
    quadrant3TextFill: Color(0xff070707),
    quadrant4TextFill: Color(0xff020202),
    quadrantPointFill: Color(0xffd4d4d4),
    quadrantPointTextFill: Color(0xff111111),
    quadrantXAxisTextFill: Color(0xff111111),
    quadrantYAxisTextFill: Color(0xff111111),
    quadrantInternalBorderStrokeFill: Color(0xffd4d4d4),
    quadrantExternalBorderStrokeFill: Color(0xffd4d4d4),
    quadrantTitleFill: Color(0xff111111),
    attributeBackgroundColorOdd: Color(0xffffffff),
    attributeBackgroundColorEven: Color(0xfff2f2f2),
    rowOdd: Color(0xffffffff),
    rowEven: Color(0xfff4f4f4),
    venn1: Color(0xff555555),
    venn2: Color(0xfff4f4f4),
    venn3: Color(0xff555555),
    venn4: Color(0xffbbbbbb),
    venn5: Color(0xff777777),
    venn6: Color(0xff999999),
    venn7: Color(0xffdddddd),
    venn8: Color(0xffffffff),
    vennTitleTextColor: Color(0xff333333),
    vennSetTextColor: Color(0xff000000),
    requirementBackground: Color(0xffeeeeee),
    requirementBorderColor: Color(0xffd4d4d4),
    requirementTextColor: Color(0xff111111),
    relationColor: Color(0xff666666),
    relationLabelBackground: Color(0xffffffff),
    relationLabelColor: Color(0xff333333),
  );

  /// Theme by its mermaid name; unknown names return [defaultTheme].
  static MermaidTheme named(String name) => switch (name) {
        'dark' => darkTheme,
        'forest' => forestTheme,
        'neutral' => neutralTheme,
        _ => defaultTheme,
      };
}
