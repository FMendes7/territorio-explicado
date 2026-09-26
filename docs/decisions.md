# Decision log

One entry per significant choice: **what** and **why**. Append-only; reversals get a new entry.

## 2026-09-26 — Enter solo, option A, track 3

Solo entry (the 144-hour window is one person's attention → small and deep). Project: an agent that
answers territorial questions in Portugal with evidence from fragmented open geodata. Primary track:
**The Agent That Can Explain Why**; tracks 1 and 2 fit without extra work but are not scored twice.
Rationale: the author's GIS/PostGIS background is the differentiator, the impact story is verifiable,
and all three sponsor layers fit naturally (Zetaris federates PostGIS + REST; Nemotron routes reasoning;
H-MEM gives memory with an audit trail).

## 2026-09-26 — Three pilot regions, not national

CIM Região de Coimbra (19 municipalities), CIM do Cávado (6) and the municipality of Lisbon.
Administrative boundaries (CAOP) national. Why: the hosting server has ~18 GB free with a disk alert at
85 %, and full national COS2023 + hazard + census would blow it; three regions keep the database ≤ 2.5 GB
and cover places the author can validate by hand (Coimbra, Esposende) plus one the jury recognises (Lisbon).

## 2026-09-26 — Nemotron-first

Reasoning via NVIDIA build (OpenAI-compatible): a large Nemotron model plans, a small one extracts and
verifies. Zero cost, complete "token layer" story, cost/latency measured in evals. The client abstracts
the provider so another model can be A/B-tested later. Local inference was ruled out: the only GPU
available has 2 GB.

## 2026-09-26 — Zetaris via Cloud Hobby (BYOC on AWS) + own MCP fallback

Zetaris Hobby is free but runs in the participant's own AWS account; the node is started only during
tests and a budget alert is set. The PostGIS source is exposed to the Zetaris node only (dedicated
container, IP allow-list, TLS, read-only role). If federation cannot push spatial functions down, plan B
is flat views + a precomputed grid-facts table (decision deadline 8 Oct). If Zetaris fails entirely, a
tiny MCP server over the same database keeps the architecture intact (losing only the sponsor points).

## 2026-09-26 — Strict pre-window / window separation

Everything built before 15 Oct is data, accounts, evaluation cases and docs, listed in `PRE-EXISTING.md`.
A private rehearsal prototype exists only to learn; nothing is copied from it. Why: rule 4 ("judged on
new work built during the hackathon"); a clean line is worth more than a head start.

## 2026-09-26 — TypeScript end to end

Node 20 + Express API, MCP TypeScript SDK client, Meterless H-MEM reference (TypeScript, zero deps)
vendored, React + MapLibre UI. Why: fewest moving parts across the sponsor stack; PostGIS does the
spatial work, the app only orchestrates.
