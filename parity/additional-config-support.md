# Additional diagram configuration

Configuration is resolved by `Mermaid.render` for both init directives and
frontmatter. `additional_config_keys_test.dart` checks each active setting
independently using a rendered SVG, then compares the two source forms.
`quadrant_config_rendering_test.dart` covers all 18 quadrant settings.

| Diagram | Active settings |
| --- | --- |
| architecture | `iconSize`, `padding`, `fontSize`, `nodeSeparation` |
| block | `padding` |
| cynefin | `width`, `height`, `padding`, `showDomainDescriptions`, `boundaryAmplitude`, `seed` |
| eventmodeling | `padding`, `rowHeight` |
| ishikawa | `diagramPadding` |
| journey | `diagramMarginX`, `diagramMarginY`, `leftMargin`, `maxLabelWidth`, `boxTextMargin`, `width`, `height`, `taskMargin`, `taskFontSize`, `taskFontFamily`, `actorColours`, `sectionFills`, `sectionColours`, `titleColor`, `titleFontFamily`, `titleFontSize` |
| kanban | `padding`, `sectionWidth`, `ticketBaseUrl` (the ticket label links to the substituted URL) |
| mindmap | `padding`, `maxNodeWidth`, `layoutAlgorithm` (supported layout choices retain the existing deterministic implementations) |
| packet | `rowHeight`, `bitWidth`, `bitsPerRow`, `showBits`, `paddingX`, `paddingY` |
| radar | `width`, `height`, all four margins, `axisScaleFactor`, `axisLabelFactor`, `curveTension` |
| requirement | `rect_fill`, `text_color`, `rect_border_size`, `rect_border_color`, `rect_min_width`, `rect_min_height`, `fontSize`, `rect_padding`, `line_height` |
| railroad | `compactMode`, `padding`, `verticalSeparation`, `horizontalSeparation`, `arcRadius`, `fontSize`, `fontFamily`, terminal/nonterminal/special colors, `lineColor`, `strokeWidth`, `markerFill`, `ruleNameColor`, `showMarkers`, `markerRadius` |
| timeline | `leftMargin`, `padding`, `disableMulticolor` |
| treemap | `padding`, `diagramPadding`, `showValues`, `nodeWidth`, `nodeHeight`, `valueFormat` |
| venn | `width`, `height`, `padding`, `useDebugLayout` (debug geometry requires text nodes) |
| wardley-beta | `width`, `height`, `padding`, `nodeRadius`, `nodeLabelOffset`, `axisFontSize`, `labelFontSize`, `showGrid` |

## Compatibility boundaries

- `useWidth`/`useMaxWidth` control browser/container sizing. A portable scene
  has intrinsic dimensions; Flutter viewport sizing remains a widget concern.
- Architecture's existing grid layout has no fcose spring/iteration state.
  `randomize`, `seed`, `numIter`, `edgeElasticity`, and
  `idealEdgeLengthMultiplier` therefore do not provide fcose behavior. This
  engine work is tracked by [#61](https://github.com/orestesgaolin/mermaid/issues/61).
- Journey/timeline schemas carry old sequence fields that their active
  upstream renderers do not use. Journey's `textPlacement` selects DOM text
  machinery; the portable renderer uses measured scene text. Timeline reads
  only its active margin, padding and multicolor options.
- Treemap declares `borderWidth`, `valueFontSize`, and `labelFontSize`, but its
  current upstream renderer does not consume these configuration fields.
  `valueFormat` supports grouping, currency prefixes, fixed-point, percentage,
  exponential and significant-digit forms (for example `,`, `$,.2f`, `.1%`,
  `.3e`, `.4g`). Other D3 formatting dialect features fall back to grouped
  numeric output; they are not claimed as full D3 formatting support.
- Railroad comment colors need a grammar that produces comment nodes. The
  supported EBNF parser strips comments. ABNF/PEG and their comment nodes are
  part of [#61](https://github.com/orestesgaolin/mermaid/issues/61).
- An explicit quadrant X position applies when there are no points. With
  points, upstream always places X labels at the bottom; the port follows it.

Configuration support does not imply exact pixel parity. The corresponding
layout approximations remain documented in the per-diagram notes.
