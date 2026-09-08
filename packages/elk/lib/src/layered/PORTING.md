# ELK layered implementation status

Current support, 2026-09-08. `ElkLayered.layout()` runs the native layered
pipeline. It does not fall back to Dagre. Acceptance of an input does not imply
that every ELK option is implemented: `unsupportedElkFeature()` currently does
not reject the accepted partial features below.

## Pipeline

| Stage | Implementation | Current behavior |
| --- | --- | --- |
| Graph/model and builder | `lgraph.dart`, `property.dart`, `elk_layered_engine.dart` | Public JSON graph, nested scopes, direction transforms, recursive layout and extraction |
| Cycle breaking | `p1_greedy_cycle_breaker.dart`, `p1_cycle_breakers.dart` | Greedy, depth-first, interactive, model-order and greedy model-order strategies; reversed-edge restoration |
| Layering | `p2_network_simplex_layerer.dart` | Network simplex with intermediate long-edge and label nodes |
| Crossing minimization | `p3_layer_sweep_crossing_minimizer.dart` | Layer sweeps, seeded Java-compatible random generator, model order, explicit port ordering |
| Node placement | `p4_bk_node_placer.dart` | Brandes–Köpf alignment/compaction; port anchors participate through generic endpoint coordinates |
| Routing | `p5_orthogonal_routing.dart` | Orthogonal routing with route restoration and intermediate processors |
| Orchestration | `elk_layered_engine.dart` | All stages execute end-to-end for flat and nested graphs |

## Feature contracts and regression evidence

Paths below are relative to `packages/elk/` unless they name a phase file above.

| Feature | Contract | Tests / tracking |
| --- | --- | --- |
| Hierarchy | Recursive child graphs; edges split through every ancestor and reassembled at their original endpoints; positioned labels retained | `test/elk_hierarchy_test.dart`, #50 |
| Nested directions | Each child graph can override its parent's direction; descendant geometry, ports, labels, junctions and cross-boundary segments are converted bottom-up into the parent frame | `test/nested_direction_test.dart`, #62 |
| Ports | Four explicit sides, spaced N/S anchors, fixed-side preservation, fixed cross-boundary ports; configurable surrounding top/bottom spacing | `test/elk_ports_test.dart`, #51 |
| Labels | Edge center/head/tail roles, explicit sides and thickness clearance; node labels, outside port labels, direction-aware coordinates | [Label contract](../../../LABELS.md), `test/elk_labels_test.dart`, #52 |
| Self-loops and sizing | Explicit side pairs, per-side loop spacing, content sizing constraints and BK edge straightening | `test/issue54_selfloop_routing_test.dart`, #54 |
| BK fixed alignment | Dart and ELK JSON options select single-pass or balanced BK compaction; NONE remains the default | `test/fixed_alignment_test.dart`, #66 |
| Advanced constraints and hyperedges | Weighted successor blocks and barycenter associates; shared-port branch expansion, critical segment splitting and junction output | `test/issue53_hyperedge_routing_test.dart`, #53 |
| Cycle strategy | JSON and Dart select the cycle breaker; interactive ordering uses supplied node centers in the selected direction | `test/cycle_breaking_strategies_test.dart`, `test/cycle_breaking_processors_test.dart`, #64 |
| Model order | Input order can constrain crossing minimization | `test/elk_spacing_modelorder_test.dart` |

Explicit port coordinates in positioned output refer to the port rectangle's
top-left. Edge endpoints use the port anchor, which can be a different point
for a nonzero-size port. Head/tail labels on deep edges refer to the original
source/target, not the enclosing compound.

Multi-endpoint edges return one section per source-target branch and retain the
original edge ID. Internal branch ports are removed from positioned output.
All graph element IDs must be globally unique. Successor and associate lists
are Dart API node references; they are not standard ELK JSON option names.
Real elkjs 0.9.3 rejects non-simple multi-endpoint input, so reference
comparisons use equivalent explicit shared-port branches.

Leaf sizes remain fixed by default. `fixedSize: false` enables content sizing
in the Dart API. JSON `NODE_LABELS` and `PORTS` select content constraints;
`MINIMUM_SIZE` preserves the supplied dimensions while that content is fitted.
Measured large nodes use their full extents in compaction. This is distinct
from the specialized upstream optimization that splits a big node across
several layers, which is not exposed by this API.

N/S ports do not require a separate BK branch in this direct-port model: the
aligner uses each port's position and anchor regardless of side. The upstream
PORT_DUMMY/EXT_PORT_SIDE side-selection rule is also already represented.
Do not infer missing behavior solely from an obsolete TODO comment.

## Validation and limits

`test/elk_vs_elkjs_test.dart` resolves fixtures from both the repository root and
package directory. It compares against retained elkjs 0.9.3 output in
`tool/validation/elkjs_golden.json`; the matching inputs are in `graphs.json`.
The suite checks structural properties such as layer order, crossing order
and leaf overlap. Compound containment is expected and is not a leaf overlap.
`tool/validation/output/` retains side-by-side SVGs. Regenerating an oracle is a
separate action from running tests against the recorded output.

The recursive hierarchy arrangement is not the complete upstream coordinated
INCLUDE_CHILDREN optimization. Dense graphs can differ in boundary port order,
edge clearance and total edge length. The seeded random implementation does
not promise the same random call sequence or bit-identical tie-breaking as
elkjs. Accepted alternative node-placement strategy names may still use BK;
consult `api/options.dart` rather than inferring an implemented strategy from
an enum member. Label automatic side selection and optimal-layer switching
remain outside the explicit placement contract.

Flowchart consumers intentionally apply their own edge clipping, markers,
labels and restyling after layout; raw ELK coordinates do not replace that
renderer behavior.

## Historical work

[Archived stage notes](PORTING_HISTORY.md) retain prior checkpoints, reversions
and old evidence counts. They are history, not the current support matrix.
