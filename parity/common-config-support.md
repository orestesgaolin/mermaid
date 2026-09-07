# Common diagram configuration support

This matrix tracks Mermaid configuration keys for the common diagram renderers.
"Scene" means that the key changes the portable `RenderScene`. "Container"
means that Mermaid.js applies the key when it creates or embeds SVG and it has
no portable scene equivalent.

| Diagram | Scene keys | Container or upstream-inert keys | Remaining renderer work |
| --- | --- | --- | --- |
| flowchart | `titleTopMargin`, `subGraphTitleMargin.top/bottom`, `diagramPadding`, `nodeSpacing`, `rankSpacing`, `curve`, `padding`, `wrappingWidth`, `defaultRenderer`, `inheritDir` | `useWidth`, `useMaxWidth`, `htmlLabels`, `arrowMarkerAbsolute` | none |
| sequence | `hideUnusedParticipants`, `activationWidth`, `diagramMarginX`, `diagramMarginY`, `actorMargin`, `width`, `height`, `boxMargin`, `boxTextMargin`, `noteMargin`, `messageMargin`, `messageAlign`, `noteAlign`, `mirrorActors`, `bottomMarginAdj`, `rightAngles`, `showSequenceNumbers`, actor/note/message font fields, `wrap`, `wrapPadding`, `labelBoxWidth`, `labelBoxHeight` | `useWidth`, `useMaxWidth`, `arrowMarkerAbsolute`, `forceMenus` | none |
| class | `titleTopMargin`, `padding`, `nodeSpacing`, `rankSpacing`, `diagramPadding`, `hideEmptyMembersBox`, `hierarchicalNamespaces` | `useWidth`, `useMaxWidth`, `arrowMarkerAbsolute`, `htmlLabels`; `dividerMargin` and `textHeight` belong to the retired v2 renderer | none |
| state | `titleTopMargin`, `padding`, `noteMargin`, `nodeSpacing`, `rankSpacing`, `forkWidth`, `forkHeight`, `radius` | `useWidth`, `useMaxWidth`, `arrowMarkerAbsolute`; `defaultRenderer` selects an upstream detector/legacy implementation rather than an intrinsic scene engine; `dividerMargin`, `sizeUnit`, `textHeight`, `titleShift`, `miniPadding`, `fontSizeFactor`, `fontSize`, `labelHeight`, `edgeLengthFactor`, and `compositTitleSize` belong to the retired v2 renderer and are not read by the unified renderer | none |
| gantt | `titleTopMargin`, `barHeight`, `barGap`, `topPadding`, `rightPadding`, `leftPadding`, `gridLineStartPadding`, `fontSize`, `sectionFontSize`, `numberSectionStyles`, `axisFormat`, `tickInterval`, `topAxis`, `displayMode`, `weekday` | `useWidth`, `useMaxWidth` | none |
| pie | `textPosition`, `donutHole`, `legendPosition`, static `highlightSlice` | `useWidth`, `useMaxWidth`; `highlightSlice: hover` requires pointer state | none |
| gitGraph | `titleTopMargin`, `diagramPadding`, `nodeLabel.width`, `nodeLabel.height`, `mainBranchName`, `mainBranchOrder`, `showCommitLabel`, `showBranches`, `rotateCommitLabel`, `parallelCommits` | `useWidth`, `useMaxWidth`, `arrowMarkerAbsolute`; `nodeLabel.x/y` are fixed offsets in the upstream renderer | none |

Both frontmatter `config:` and every `%%{init}%%` directive use the same typed
readers. Later init values replace earlier frontmatter values, matching Mermaid.
