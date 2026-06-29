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

### G1 — Cross-hierarchy long/back-edge routing region  ✅ FIXED
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

**Prototyped & reverted (promising, not yet robust):** flipped `_phaseCrossmin`
to bottom-up and added `_inheritChildPortOrder` (sort each compound node's
external ports by their border dummy's within-layer index in the minimized
child). Result on the corpus:
- **churn reached width parity** (929→1044px vs elkjs 1054) and most clustered
  diagrams held parity (nested_td/lr, d2, simple 193≈195, st 233≈227).
- **but orig regressed** 1091→1323px (elkjs 1027): its BAA cluster spread wide.
  orig and churn are near-identical (churn just adds Churnkey + one edge), so
  the wild divergence shows the inheritance isn't stable yet.
**Resolved (second pass):** the first attempt only *reordered* `cn.ports`, which
the parent sweep then re-distributed by barycenter — so the inheritance was
half-applied and unstable. Fix: sort the cross-hierarchy ports **per side**
(entry dummies and exit dummies are in different child layers, so indices are
only comparable within a side) **and mark the order fixed** (`p3.portOrderFixed`)
so the parent sweep keeps it. Result on the corpus:
- **orig and churn both reach width parity** (orig 1091→1036 vs 1027; churn
  929→1058 vs 1055) with no BAA spread.
- DOVEAPI→DOVE now routes straight up the **near** side instead of detouring to
  the far-left margin.
- **No regressions:** every other corpus diagram is unchanged and at parity
  (nested_td/lr, d2, simple 193≈195, st 233≈227, flat_td 268≈265). elk 33 +
  core 414 green.

### G2 — Intra-cluster node ordering  ✅ addressed by G1
**Seen in:** churn (BAA arranged 3+3 vs elkjs 4+2; which nodes sit adjacent).
**Symptom:** nodes inside a cluster land in a different within-layer order, so
the cluster's internal edges and its entry/exit points differ from elkjs.
**Root cause:** a cluster's crossing-min doesn't account for the *direction*
cross-hierarchy edges enter/leave it, because the parent coordination (G1) is
missing — the external-port dummies aren't ordered by the parent-side geometry.
**Fix:** falls out of G1 (the coordinated sweep orders border dummies by the
inherited parent order, which then biases the inner crossing-min correctly).

### G3 — Cycle-break / layering tie-break  ⛔ PARKED (intractable)
**Seen in:** d1 (elkjs puts Debug **above** the diamond → short feedback; ours
puts it below → wrapping back-edge; ours 281px wide vs elkjs 230px).
**Symptom:** for a 2-cycle (B→D, D→B) we reverse the opposite edge from elkjs.
**Root cause:** elkjs's `GreedyCycleBreaker.chooseNodeWithMaxOutflow` picks a
**random** node among the max-outflow ties via the layout's shared
`java.util.Random`. The pick is therefore a function of the *global* RNG state
at cycle-break time, which depends on every prior random draw in the run — not
something we can reproduce from the seed alone.
**Investigated & reverted:** added a faithful `JavaRandom.nextInt` and used a
fresh `Random(1)` for the tie-break. It flipped d1 to match elkjs (281→202,
Debug above) but **regressed `simple` 193→440** — proof that elkjs's RNG is not
fresh at this point (same seed, different pick per diagram). Kept the
deterministic first-node pick (matches more of the corpus); kept `nextInt` as a
faithful primitive for later. **No deterministic rule matches both d1 and simple
(first works for simple, last for d1), so this gap is left as-is.**

### G4 — State-diagram choice/branch placement  ★ (minor, G1-adjacent)
**Seen in:** st (choice diamond + Connected/Backoff positions differ slightly).
**Symptom:** small placement differences around the choice node and the retry
back-edge.
**Root cause:** crossing-min + the same coordination as G1/G2.
**Fix:** largely subsumed by G1; revisit after.

## Status

- **G1 ✅ fixed** — bottom-up crossing-min with per-side, fixed-order child port
  inheritance. orig + churn at width parity; cross-hierarchy back-edges route the
  near side.
- **G2 ✅** — intra-cluster ordering fell out of G1 (no more cluster spread).
- **G3 ⛔ parked** — cycle-break tie-break is RNG-global, intractable (d1 only).
- **G4** — re-check state choice placement now that G1 landed; minor if anything.

Everything else (sizing, labels, spacing, clearance, hand-drawn) is at parity.
Remaining known divergence: d1's feedback-node side (G3), cosmetic.
