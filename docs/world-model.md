# Meterless World Model — integration notes (design only; the code is written inside the window)

Read on 2026-09-27: the Meterless World Model agent-engine guide (HackOS participant resources) and the public repository
[`Meterless/Meterless`](https://github.com/Meterless/Meterless) at commit `0aa7417` (2026-07-22), folder
`engines/world-model/`. The reference implementation was run in a scratch directory **outside this repository** on the
laptop (Node 20.20.2): unit tests 10/10, conformance runner 8/8. Nothing from it is copied here before the window.
Design context: `architecture.md` ("Shared case state") and `decisions.md` (2026-09-27).

## 1. What the reference gives us (facts from the code)

| Aspect | Reference (`engines/world-model/reference/src`) |
|---|---|
| Package | `@meterless/world-model-reference` 0.1.0, TypeScript, **Apache-2.0**, **no runtime dependencies** (dev only: tsx, vitest, esbuild); ~1 570 lines in `index`, `ingest`, `resolve`, `stableIds`, `store`, `types` |
| Writes | `upsertEntity`, `upsertContext`, `relate`, `assertFact` (+ `ingest` for feeds). **Every write needs provenance** `{kind, at, by?, url?, checksum?, runId?}`; a write without it is rejected |
| Reads | `view("graph")`: `entity`, `neighborsOf(id, {via, inContext, at})`, `incoming`, `entitiesInContext`, `traverse` (one edge type), `query` · `view("facts").about(id)` · `view("snapshot").entityAt(id, at)` · `view("timeline")` · `registerView` (custom reducer over events) · `events()`, `audit()`, `subscribeEvents(fn)`, `stateShapeCanonical()` |
| Identity | content-addressed ids; with an external key the id is `type:system:id` (e.g. `feature:dgt_ren:7`) |
| Edges | bitemporal (`validFrom` / `validTo`); `relate` is idempotent (same content = no-op); a new open edge with the same `(from, type, context)` and a different target **closes** the previous one |
| Facts | `assertFact` under a conflict policy (`most-recent-wins` by default; `highest-confidence-wins`, `source-priority`, `manual`); losing facts are kept with `supersededBy` |
| Time | record timestamps come from `provenance.at`, never from the wall clock (this is what makes re-runs idempotent) |
| Storage | `"memory"` (in-process) or `"local"` (one JSON file `.world/<namespace>.json`, rewritten on every write) |
| Concurrency | one FIFO write queue per instance |

## 2. Mapping to this project

| Our element | Primitive | Key (never a free-text name) | Written by |
|---|---|---|---|
| Run | context `run` | `run_id` | Intake |
| Municipality | context `municipality` | DICO | Intake |
| Place (point or drawn plot) | entity `place` | `run_id` + hash of the geometry | Intake |
| Intent | entity `intent` | profile id in `data/pretensoes.json` | Intake |
| Dataset | entity `dataset` | `dataset_meta` id (publisher, licence, reference date in attrs) | Evidence Tracer |
| Feature touched (PDM class polygon, REN/RAN, flood extent, burned area, protected area, COS polygon) | entity `feature` | `dataset:feature_id` | Evidence Tracer |
| Legal instrument | entity `diploma` | official reference (DR number) + PDF URL in attrs | Evidence Tracer |
| Rule | entity `rule` | `intent:rule_id` (type LEGAL or TECHNICAL, threshold and citation in attrs) | Rule engine |
| Evidence item | entity `evidence` | hash of dataset + SQL text + geometry reference | Evidence Tracer |
| Claim | entity `claim` | hash of run + rule + feature set | Rule engine / Planner |
| Unknown | entity `unknown` | layer + reason | any role |
| Challenger verdict | **fact** about the claim, predicate `verdict` | — (latest wins, history kept) | Challenger |

Edges, with the direction chosen so that two live edges never share `(from, type, context)` (see §3.1):

| Edge | Properties | Note |
|---|---|---|
| `feature —overlaps→ place` | share of the plot, area (m²), context = run | many features per place: `from` differs, so none closes another |
| `feature —from_dataset→ dataset` · `feature —governed_by→ diploma` | — | one each |
| `evidence —about→ feature` · `evidence —supports→ claim` | SQL text, geometry reference | many evidence items per claim |
| `claim —applies→ rule` | LEGAL / TECHNICAL | one rule per claim |
| `dataset —contradicts→ dataset` | context = the claim | the context keeps two contradictions from one source apart |
| Time series (COS 1995 → 2018 → 2023 → 2025, burned areas 1975–2025) | explicit `validFrom` / `validTo` from the edition or fire date | set explicitly, not by automatic closing, so the write order cannot corrupt the intervals |

- **Verdicts as facts:** value `{verdict: accept | reject | revise, round, rubric: {accuracy, appropriateness,
  actionability}, reason}`, `confidence` = rubric total / 9. The claim's current verdict is the winning fact; earlier
  rounds stay in `view("facts")` — the revision history is visible, not overwritten.
- **Timestamps:** writes derived from data use the dataset's reference date; role writes use a run clock (run start plus
  a step counter), fixed in `SAMPLE_MODE`. Wall-clock times go only to `logs/trace-<run_id>.jsonl`. Two sample runs on
  the same input should then produce the same `stateShapeCanonical()` — a determinism check for the sample mode.
- **Explanation graph:** our own query over the events (answer ← claims with verdict `accept` ← evidence ← feature ←
  dataset / diploma, plus rule), because `traverse` follows one edge type. A pure function of the event list, so the
  same function runs on the live model and on the log (§5).

## 3. Pitfalls found in the reference (scratch probe, 2026-09-27)

1. **Edges close each other.** Probe: `place —intersects→ A`, then `place —intersects→ B` → only B is live. A plot that
   touches a PDM class and a REN area would silently lose one link. Rule: direction `feature → place` (or a distinct
   context) for every multi-valued relationship; a unit test for it in the window.
2. **Name-keyed entities are fuzzy-merged** (similarity ≥ 0.85 merges automatically, 0.82–0.85 queues for review).
   Two PDM class names ("Espaço Agrícola de Produção" / "de Conservação") scored 0.73 and did not merge, but nothing
   prevents a closer pair from merging. Rule: always pass an external key; no name-keyed entities.
3. **`"local"` storage is not an append log:** it rewrites one pretty-printed JSON file on every write. We use
   `"memory"` plus `subscribeEvents`, appending one JSON line per event to `logs/world-<run_id>.jsonl`; across runs the
   same lines go to PostgreSQL schema `agent` (JSONB, own role, never `open`). No `.world/` files in the container.
4. **No public call to load an event list.** Rebuilding from our log means re-issuing the writes, in order, into a fresh
   instance; ids are content-addressed and timestamps come from provenance, so the rebuilt state should match — to be
   proven by the check in §5, not assumed.
5. **Examples drift from the code:** `examples/agent-run-world-state` calls `view("snapshot").contextAt()`, which the
   reference does not implement (only `entityAt`). Build against `reference/src`, not the examples.
6. **One write queue per instance:** one instance per run (`namespace = run_id`); concurrent runs never share one.

## 4. Not used (stated in each run's first trace line — what is live and what is not)

`ingest()` and its story clustering and velocity scores (no feeds here); the merge-review queue and the operator
control-plane page (headless, no human at run time); enrichment jobs and embeddings; a Neo4j substrate (only if the
organizers confirm Neo4j as a partner). H-MEM stays optional as the memory subsystem; the World Model stays either way.

## 5. Entering the repository (inside the window)

- Copy `engines/world-model/reference/src` at a pinned commit into `third_party/meterless-world-model/` with its
  `LICENSE` and a `NOTICE` line (commit, date, local changes); listed in the README's "Third-party code and licences".
- A thin adapter of our own: keyed writes (§2), the JSONL sink, the explanation query, the replay check.
- Checks, run by the evaluation runner: the Meterless conformance runner against the copied code (8/8); **replay** —
  rebuild from `logs/world-<run_id>.jsonl` and compare `stateShapeCanonical()` with the live run on
  `input_examples/example_1..3`; the edge-direction test (§3.1); two `SAMPLE_MODE` runs on `example_1` → identical state.
- Slots: `plano-janela.md` Thu 15 21:00–22:30 (store and log inside loop v0) and Fri 16 19:00–20:30 (explanation graph).
