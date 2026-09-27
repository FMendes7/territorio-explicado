# Questions to the organizers (paste-ready)

Official channel: the **Support** button in HackOS (all support during the event happens there); a copy in the Discord
`#hackathon-help` channel is fine before the event. Record every answer, dated, in `docs/lessons.md`.

Updated 2026-09-27 after reading the HackOS participant resources. Already answered by them: any agent framework is fine
and not scored (the GenAI Agentic Protocol is not mentioned); solo participation is allowed; a submission can be updated
until the deadline; sponsor technology is available to all participants and scored under Sponsor Tech.

## 1. Rules — send now (decides the track before the 15 Oct lock)

```
Hi — solo builder, a few questions on the rules before I lock my track.

The Official Rules on the event page allow "clearly declared pre-existing components" (sections 4-5). The FAQ in HackOS
says projects in the four main tracks must be built during the window and that pre-existing code is only allowed in the
Tinkerer Track, and that the Rules prevail. The "Official Rules" document in the HackOS resources is marked "working
draft" and lists other tracks (Fragmented / Autonomous Intelligence / Persistent Memory / Real-World Industry) and
partners (Zetaris, Neo4j, Meterless).

My case: before the window I loaded open geodata into PostGIS and wrote the ETL scripts and SQL lookup functions over
it (facts for a point or a drawn plot, a grid of constraints around it). All of it is declared in a PRE-EXISTING.md
in the repo. The agent itself - loop, tools, model router, verifier, UI, evaluation runner - is written inside the
window.

1. Is that eligible in Track 3 ("The Agent That Can Explain Why") with the data platform declared as a pre-existing
   component, or should it go to the Tinkerer Track?
2. If Tinkerer: is it judged and awarded from the same prize pool as the four main tracks?
3. Track changes: the FAQ says the track locks at the end of Day 1 (Oct 15); Rule 3 on the event page says it can
   change until the submission deadline. Which one applies?
4. The HackOS documents score out of 100; the event page adds up to 30 bonus points (open source, evals, documented
   failure modes). Does the bonus apply?
5. Which tracks and partner list are current: the event page (4 tracks + Tinkerer; NVIDIA, Zetaris) or the HackOS
   draft rules / AI Usage Policy (Neo4j instead of NVIDIA)? Does NVIDIA (Nemotron) count under Sponsor Tech?

Thanks!
```

## 2. Sponsor setup — send after the 7 and 8 Oct workshops, only what they did not answer

```
Hi — a few setup questions on the sponsor technology:

1. Zetaris: is there a hosted sandbox / MCP endpoint for participants, or should we create our own Zetaris Cloud
   (Hobby, BYOC) account? If our own: does the Hobby tier expose the MCP endpoint (…:8009/mcp)?
2. Zetaris + PostGIS: does federation over a PostgreSQL source push spatial functions (ST_Intersects, ST_Transform)
   down to the source, or should we expose flat views / precomputed tables?
3. NVIDIA: are there event credits on build.nvidia.com beyond the standard free tier, and which Nemotron model ids
   are recommended?
4. Deployment: is a public URL required, or is a container image plus one-command instructions enough if the URL is
   behind a shared password?

Thanks!
```
