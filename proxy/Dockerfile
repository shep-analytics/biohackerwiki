FROM alpine:3.20 AS sum
RUN apk add --no-cache jq
COPY studies/studies.json /studies.json
RUN jq '{studies: (.studies | length), topics: (.stats | keys | length), generated: .generated}' /studies.json > /summary.json

# Official Caddy plus one module, replace-response, for the homepage <title>
# rewrite in the Caddyfile. Pinned to a commit (the module has no releases).
FROM caddy:2-builder-alpine AS caddy
RUN xcaddy build --with github.com/caddyserver/replace-response@80962887e4c680abfd1b11ce1403fa8cc0fdd3d6

FROM caddy:2-alpine
COPY --from=caddy /usr/bin/caddy /usr/bin/caddy
RUN apk add --no-cache postgresql16-client curl jq
COPY Caddyfile /etc/caddy/Caddyfile
COPY brand /srv/brand
COPY studies /srv/studies
COPY --from=sum /summary.json /srv/studies/summary.json
COPY sitemap.xml robots.txt /srv/seo/
COPY relay.sh start.sh /
RUN chmod +x /relay.sh /start.sh
CMD ["sh", "/start.sh"]
