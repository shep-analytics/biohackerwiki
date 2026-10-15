FROM caddy:2-alpine
COPY Caddyfile /etc/caddy/Caddyfile
COPY brand /srv/brand
COPY studies /srv/studies
CMD ["caddy", "run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]
