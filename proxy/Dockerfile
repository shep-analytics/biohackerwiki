FROM alpine:3.20 AS sum
RUN apk add --no-cache jq
COPY studies/studies.json /studies.json
RUN jq '{studies: (.studies | length), topics: (.stats | keys | length), generated: .generated}' /studies.json > /summary.json

FROM caddy:2-alpine
RUN apk add --no-cache postgresql16-client curl jq
COPY Caddyfile /etc/caddy/Caddyfile
COPY brand /srv/brand
COPY studies /srv/studies
COPY --from=sum /summary.json /srv/studies/summary.json
COPY sitemap.xml /srv/seo/sitemap.xml
COPY relay.sh start.sh /
RUN chmod +x /relay.sh /start.sh
CMD ["sh", "/start.sh"]
