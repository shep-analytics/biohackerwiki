#!/bin/sh
# Correction relay in the background (never blocks caddy), caddy in the foreground.
while true; do sh /relay.sh; echo "relay exited, restarting"; sleep 30; done &
exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
