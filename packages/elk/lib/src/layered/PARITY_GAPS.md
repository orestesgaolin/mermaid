# elkjs parity — gap audit

Snapshot of where our ELK layout matches mermaid.js (elkjs) and where it
doesn't, from a side-by-side oracle run over a 9-diagram corpus (flat/nested ×
TD/LR, a 2-cycle decision graph, a state diagram, and the BAA/GCP/NB diagram).
Each diagram was rendered through real mermaid-cli (elkjs) and our pipeline and
compared geometrically.

## What already matches (no action)

- **Flat graphs** (TD and LR): node placement, layering, edge routing — parity.
  Dims: flat_td 268 vs 265, flat_lr/cycle within ~3px.
- **Cyclic non-nested graphs**: cycle routing matches.
- **Simple nested chains** (nested_td, nested_lr, d2): cluster placement and
  through-edges match; dims within ~3–4%.
- **Edge labels**: centred on the line with opaque background (recent fixes).
- **Edge↔cluster clearance + parallel-edge spacing**: base-value-derived (recent
  fixes); no more border hugs or thick bundles.
- **Hand-drawn fills**: render as solid (legible) in dark mode (recent fix).
- **Overall size**: within a few % on every corpus diagram except d1/churn.

## Gaps, ranked by impact

### G1 — Cross-hierarchy long/back-edge routing region  ★★★ (dominant)
**Seen in:** churn (DOVEAPI→DOVE, the de-identified edges, TM↔* edges), simple
(F→B), d1 (D→B).
**Symptom:** a long edge that leaves one cluster and enters another far away
routes through interior margins/gaps and picks the wrong wrap side, instead of
wrapping cleanly around the **outside perimeter** like elkjs. Concretely
DOVEAPI→DOVE detours to the far-LEFT margin then crosses the whole width back to
the right, where elkjs wraps up the near side / over the top.
**Root cause:** crossing-min runs **parent-first**. When the root orders a
cross-cluster edge's long-edge dummy, each cluster is a single index-0 node, so
the dummy gets barycentre 0 and is ordered leftmost; BK then places the chain
far-left. The parent never learns where the child's external ports actually sit.
**Fix:** coordinated **bottom-up** crossing-min — minimize children first, then
have the parent inherit each cluster's external-port order from the child's
border (elkjs `GraphInfoHolder` + `setPortOrderOnParentGraph`). Large,
regression-sensitive; this is the same area C2b botched (caused the band), so it
must inherit child order rather than copy parent order.

### G2 — Intra-cluster node ordering  ★★ (same root cause as G1)
**Seen in:** churn (BAA arranged 3+3 vs elkjs 4+2; which nodes sit adjacent).
**Symptom:** nodes inside a cluster land in a different within-layer order, so
the cluster's internal edges and its entry/exit points differ from elkjs.
**Root cause:** a cluster's crossing-min doesn't account for the *direction*
cross-hierarchy edges enter/leave it, because the parent coordination (G1) is
missing — the external-port dummies aren't ordered by the parent-side geometry.
**Fix:** falls out of G1 (the coordinated sweep orders border dummies by the
inherited parent order, which then biases the inner crossing-min correctly).

### G3 — Cycle-break / layering tie-break  ★★ (independent)
**Seen in:** d1 (elkjs puts Debug **above** the diamond → short feedback; ours
puts it below → wrapping back-edge; ours 281px wide vs elkjs 230px).
**Symptom:** for a 2-cycle (B→D, D→B) we reverse the opposite edge from elkjs,
so the feedback node is layered on the other side.
**Root cause:** our GreedyCycleBreaker's tie-break (which edge of a cycle to
reverse) differs from elkjs's (it depends on DFS/source-sink order and
out-flow). Independent of the hierarchy work.
**Fix:** match elkjs `GreedyCycleBreaker` ordering exactly (sources/sinks
selection + tie-break). Self-contained, medium effort, but touches every cyclic
diagram so it needs the corpus guard.

### G4 — State-diagram choice/branch placement  ★ (minor, G1-adjacent)
**Seen in:** st (choice diamond + Connected/Backoff positions differ slightly).
**Symptom:** small placement differences around the choice node and the retry
back-edge.
**Root cause:** crossing-min + the same coordination as G1/G2.
**Fix:** largely subsumed by G1; revisit after.

## Recommended order

1. **G3** first — self-contained, unblocks d1, lowest risk, good warm-up that
   proves the corpus-guard loop.
2. **G1** — the dominant, architectural one. Do it bottom-up and incrementally
   (children inherit, parent follows), gating each step on the corpus + oracle.
   G2 and G4 fall out of it.

Everything else (sizing, labels, spacing, clearance, hand-drawn) is at parity.
