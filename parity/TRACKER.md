# Mermaid support and parity tracker

Current support, 2026-09-08. All 28 registered diagram types produce portable
scenes and support Flutter/SVG output. This is type coverage, not full layout
or pixel parity with Mermaid.js.

## Current contracts

- [Common diagram configuration](common-config-support.md)
- [C4, ER and XY configuration](c4-er-xy-config-support.md)
- [Additional diagram and quadrant configuration](additional-config-support.md)
- [Solver and grammar compatibility](COMPATIBILITY.md)
- [ELK implementation and remaining limitations](../packages/elk/lib/src/layered/PORTING.md)

Active scene configuration resolves through init directives and frontmatter.
Browser container behavior, upstream-inactive fields and approximate solvers
are separate from supported scene configuration. Per-node directives are a
separate parser/style feature.

## Changes in the current maintenance pass

| Ticket | Behavior | Evidence |
| --- | --- | --- |
| #44 | Active per-diagram configuration | `additional_config_keys_test.dart`, `common_diagram_config_test.dart`, `c4_er_xy_config_test.dart`, quadrant and diagram-specific suites |
| #45 | Push/PR and release checks share `tool/check.sh` | Actionlint plus local execution; a local pass does not establish a GitHub run |
| #46 | ER horizontal cell padding defaults to 20 | `er_pie_gantt_test.dart`; retained Mermaid.js reference render |
| #47 | CSS colors including HSL/HSLA | `color_test.dart` |
| #48 | `MermaidView.onSceneChanged` | `mermaid_view_test.dart` |
| #49 | Shared scene, geometry, widget, PNG and evidence test helpers | Existing core and Flutter integration suites |
| #50 | Deep ELK edge endpoints and retained labels | `elk_hierarchy_test.dart`; elkjs reference fixture |
| #51 | Four-side ELK ports and surrounding spacing | `elk_ports_test.dart`; four direction reference fixtures |
| #52 | ELK edge/node/port labels | `elk_labels_test.dart`; [label contract](../packages/elk/LABELS.md) |
| #53 | Weighted successor constraints, shared-port hyperedge branches and junction output | `issue53_hyperedge_routing_test.dart`; retained elkjs comparison |
| #54 | Four-side self-loops, content sizing and BK edge straightening | `issue54_selfloop_routing_test.dart` |
| #55 | Registered Kanban icons, defined missing-icon fallback | `kanban_icon_test.dart`, `kanban_icon_render_test.dart` |
| #56 | Kanban styles, links and tooltips | Core and Flutter directive integration tests |
| #57 | Requirement styles, links and callback metadata | Core and Flutter directive integration tests |
| #58 | Git right-to-left chronology and annotations | `issue58_git_rl_test.dart`; retained LR/RL render pair |
| #59 | Adjacent class notes with zero-length rank constraint | `issue59_class_note_adjacency_test.dart`; TB/LR renders |
| #61 | Explicit solver/grammar contract | [Compatibility contract](COMPATIBILITY.md) |

Local commits and validation evidence establish implementation status; issue
closure and remote CI are separate repository operations.

## Evidence boundaries

`tool/check.sh` runs analysis, ELK/core/Flutter/app tests and package publication
dry runs. Parser/geometry tests, PNG integration tests and inspected render
samples establish different properties. None alone establishes exact pixel
parity across all inputs, browsers, fonts and Mermaid.js versions.

Flowchart-specific edge clipping, arrow shortening, label placement, cluster
translation and paint-only restyling are intentional renderer behavior. Do not
replace them solely to match a general layout engine's raw coordinates.

## Historical investigations

The 28 diagram notes in this directory retain the detailed investigations and
implementation history. Their old “full-parity” labels and counts apply only
to that pass and its fixtures. The
[archived June parity table](history/2026-06-parity-pass.md) records those claims
separately; current contracts and regression evidence above take precedence.
