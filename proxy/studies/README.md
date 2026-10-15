# Study browser (/studies)
Static page served by the proxy, no Outline involved.
Update data: `cp /workspace/bw-studies/studies.json proxy/studies/studies.json && git commit && git push` (Railway redeploys).
If `studies.json` is missing, the page loads `studies.sample.json` and shows a SAMPLE DATA banner.
Fields: topic, pmid, title, first_author, year, journal, design, n, score (1-5), score_reason, finding, url.
