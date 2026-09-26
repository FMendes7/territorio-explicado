# Questions to post on the event Discord (paste-ready)

Post in the general/questions channel after registering. Record the answers in `docs/lessons.md`.

---

Hi all — solo builder here, preparing for the 15 Oct window. A few practical questions so I set up the right things beforehand:

1. **Zetaris:** will there be a hosted sandbox/MCP endpoint for participants, or should we create our own Zetaris Cloud (Hobby, BYOC on AWS) account? If our own: does the Hobby tier expose the MCP endpoint (`…:8009/mcp`)?
2. **Zetaris + PostGIS:** does federation over a PostgreSQL source push spatial functions (`ST_Intersects`, `ST_Transform`) down to the source, or should we expose flat views/precomputed tables?
3. **NVIDIA:** are there event credits on build.nvidia.com beyond the standard free tier, and which Nemotron model ids are recommended for the "token layer" workshop?
4. **GenAI Agentic Protocol / AgentOS:** is it required or recommended for this edition, or is any stack fine as long as it is documented?
5. **Pre-existing components:** I plan to load open geodata (DGT/ICNF/APA/INE) into PostGIS *before* the window and declare it as a pre-existing data component in the submission; the agent itself will be written inside the window. Is that the intended reading of rule 4/5?
6. **Deployment:** is a public URL required, or is a container image plus one-command instructions sufficient if the URL is behind a shared password?

Thanks!
