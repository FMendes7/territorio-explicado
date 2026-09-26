# Build-window script (15–20 Oct 2026) — hour-level plan to be detailed by 14 Oct

All times Europe/Lisbon (UTC+1). Window: Thu 15 Oct 01:00 → Wed 21 Oct 00:45. Submit Mon 19 evening;
Tue 20 is buffer.

| Day | Goal | Done when |
|---|---|---|
| Thu 15 | Repo `app/` created, `mvp new territorio -t node`, API skeleton, agent loop v0, tools `geocode` + `zetaris.run_sql` + `pg.facts_at`, JSONL logs | one question answered end-to-end with raw evidence |
| Fri 16 | LLM router (Super/Nano), evidence schema + verifier, H-MEM memory + trust ledger, IPMA tool | 10 golden cases pass; evidence on every claim |
| Sat 17 | UI: map (MapLibre) + evidence panel + step trace, PT/EN strings; **midpoint check: "if the deadline were tomorrow, what fails?"** | demo flow works in a browser |
| Sun 18 | `evals/run.ts`, results committed; `docs/failure-modes.md` finalised; `docker compose up` from a clean clone with `data/sample/` | numbers in README; clean run on another machine |
| Mon 19 | Public URL (`mvp auth territorio off`), video ≤3 min, README, `docs/sponsor-fit.md` measured sections, submission form | **submitted** |
| Tue 20 | Buffer; resubmit only if strictly better | — |

## Fixed rituals

- Morning: read Discord announcements; commit early, commit often (timestamps break ties).
- Every tool/model call logged; every eval run dated.
- Anything copied from outside the window → `PRE-EXISTING.md`.
