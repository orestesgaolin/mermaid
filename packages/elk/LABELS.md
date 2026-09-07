# Label layout

Labels retain measured width, height and text in positioned output. The engine
does not measure fonts. `ElkLabel.placement` selects CENTER, HEAD (target), or
TAIL (source); `side` explicitly selects above or below in internal flow
coordinates. Above is the Dart default. Automatic ELK side-selection heuristics
and optimal-layer switching are not implemented.

Center labels reserve a layout dummy; head/tail labels follow the original
endpoint segments, including deep hierarchy crossings. Stacks use
`spacingLabelLabel`, route clearance uses `spacingEdgeLabel` plus half the edge
`thickness`, and vertical output transposes stacking while keeping text upright.
Self-loop labels follow the exterior routed segment. Label bounds contribute
to graph bounds.

Leaf node labels default to their original top-left position. Explicit
`ElkNodeLabelPlacement` supports top-left, top-center, center and bottom-center;
compound labels default to the reserved top band. `spacingNodeLabel` controls
the top/bottom inset. JSON accepts `elk.nodeLabels.placement` with INSIDE
H_CENTER and V_TOP/V_CENTER/V_BOTTOM combinations.

Port labels use exterior corners with `spacingPortLabel`: north above/right,
east and south below/right, west below/left. Coordinates are relative to the
port's top-left and remain correct after direction transforms. The public
positioned port includes its labels; node labels remain node-relative; edge
labels use root coordinates. These measured-box rules do not emulate HTML or
font rendering.

`test/elk_labels_test.dart` exercises node/port/edge labels in all four
orientations, cross-hierarchy end roles, self-loops, JSON options, containment,
and comparative edge-thickness clearance. Port corner expectations were
checked against elkjs 0.9.3. This is behavioral coverage, not identical
coordinates for every graph.
