# Layout and grammar compatibility contract

Current scope, 2026-09-07. This contract resolves the scope decision in
[#61](https://github.com/orestesgaolin/mermaid/issues/61). Supporting a diagram
means accepting the documented syntax and producing a portable scene. It does
not promise identical coordinates, font metrics, or pixels to Mermaid.js.

| Area | Supported behavior | Deliberate boundary | Regression evidence |
| --- | --- | --- | --- |
| Architecture | Services, groups, nested groups, junctions, port-side edges and row/column alignment in a deterministic grid | No fcose force simulation or equivalent solver parameter behavior | [fixtures](../packages/mermaid_core/test/fixtures/configuration/architecture.mmd), [render tests](../packages/mermaid_core/test/new_types_test.dart), [configuration tests](../packages/mermaid_core/test/additional_config_keys_test.dart) |
| Mindmap | Hierarchy, node shapes, labels, styles and configurable deterministic tree placement | No cose-bilkent solver; relative branch placement can differ from Mermaid.js | [fixture](../packages/mermaid_core/test/fixtures/configuration/mindmap.mmd), [render tests](../packages/mermaid_core/test/xychart_mindmap_req_c4_test.dart), [configuration tests](../packages/mermaid_core/test/additional_config_keys_test.dart) |
| Venn | Sets and intersections with validated membership, labels, configurable dimensions and deterministic approximate placement | Three or more sets use a relaxation heuristic rather than the venn.js area optimizer; styled intersection fill is an approximation rather than an exact lens | [fixture](../packages/mermaid_core/test/fixtures/configuration/venn.mmd), [render tests](../packages/mermaid_core/test/niche_types_test.dart), [configuration tests](../packages/mermaid_core/test/radar_venn_treemap_config_test.dart) |
| Railroad | EBNF rules, sequences, choices, groups, optional/repeated expressions and special sequences | ABNF/PEG are not accepted grammar contracts; EBNF comments are stripped, and paths approximate circular arcs | [fixture](../packages/mermaid_core/test/fixtures/configuration/railroad.mmd), [render tests](../packages/mermaid_core/test/niche_types_test.dart), [configuration tests](../packages/mermaid_core/test/additional_config_keys_test.dart) |

The supported configuration keys and their limits are listed in
[additional configuration support](additional-config-support.md). Browser
container sizing and DOM/HTML behavior have no automatic portable scene
counterpart. An upstream schema field that the upstream renderer does not use
is not evidence of an implemented renderer feature.

These boundaries remain the current product contract. Exact solver parity and
ABNF/PEG support are not requirements of this backlog pass. Expanding either
requires a concrete consumer input, expected output or reference version, and
acceptance criteria for the new behavior. Such a request should become a
separate fixture-backed implementation ticket, rather than reopening an
unbounded promise of full parity.

The linked tests establish parser, geometry, and configuration behavior.
Historical visual comparisons in the individual diagram notes apply only to
their recorded fixtures and versions. They do not establish general pixel
parity or refresh themselves when implementation changes.
