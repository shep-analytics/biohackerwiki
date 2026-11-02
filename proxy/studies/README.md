# Study browser (/studies)
Static page served by the proxy, no Outline involved.
Update data: `cp /workspace/bw-studies/studies.json proxy/studies/studies.json && git commit && git push` (Railway redeploys).
Format: {generated, definition, stats:{topic:{found,listed}}, studies:[{topic, pmid, title, first_author, year, journal, design, n, studies_pooled, design_n, score 1-5, score_reason, finding, url}]}.
`summary.json` (study and topic counts plus `generated`) is generated at build time from `studies.json` by the Dockerfile and used by the home page counts.
