#!/bin/sh
# Correction relay: emails new Wiki.js comments to the corrections inbox via Resend.
# Runs alongside caddy (see start.sh). Notes in RELAY.md.

RELAY_TO=${RELAY_TO:-corrections@biohackerwiki.com}
RELAY_FROM=${RELAY_FROM:-Biohacker Wiki <noreply@biohackerwiki.com>}
RELAY_INTERVAL=${RELAY_INTERVAL:-60}
case $RELAY_INTERVAL in ''|*[!0-9]*) RELAY_INTERVAL=60 ;; esac

log() { echo "relay: $*"; }

if [ -z "$RELAY_DB_HOST" ] || [ -z "$RELAY_DB_PASS" ]; then
	log "relay disabled"
	while :; do sleep 3600; done
fi

export PGHOST="$RELAY_DB_HOST"
export PGPORT="${RELAY_DB_PORT:-5432}"
[ -n "$RELAY_DB_NAME" ] && export PGDATABASE="$RELAY_DB_NAME"
[ -n "$RELAY_DB_USER" ] && export PGUSER="$RELAY_DB_USER"
export PGPASSWORD="$RELAY_DB_PASS"
export PGOPTIONS="-c client_min_messages=warning"

umask 077
tmp=$(mktemp -d) || { log "mktemp failed"; exit 1; }
trap 'rm -rf "$tmp"' EXIT

# q SQL [psql args]: run SQL from stdin so :'var' interpolation works.
q() {
	sql=$1
	shift
	printf '%s\n' "$sql" | psql -v ON_ERROR_STOP=1 -X -q -At "$@"
}

until q "
CREATE TABLE IF NOT EXISTS bw_relay_sent(comment_id int primary key, sent_at timestamptz default now(), resend_id text);
ALTER TABLE bw_relay_sent ADD COLUMN IF NOT EXISTS last_event text;
CREATE TABLE IF NOT EXISTS bw_relay_state(k text primary key, v int);
INSERT INTO bw_relay_state(k, v) SELECT 'watermark', coalesce(max(id), 0) FROM comments ON CONFLICT (k) DO NOTHING;
" >/dev/null; do
	log "db not ready, retrying in 10s"
	sleep 10
done
log "started, watermark $(q "SELECT v FROM bw_relay_state WHERE k = 'watermark'")"

send_one() {
	row=$1
	id=$(printf '%s' "$row" | jq -r '.id')
	case $id in ''|*[!0-9]*) log "bad comment row"; return 1 ;; esac

	jq -n --arg to "$RELAY_TO" --arg from "$RELAY_FROM" --argjson r "$row" '
		($r.email // "") as $e
		| {
			from: $from,
			to: [$to],
			subject: "Correction: \($r.title // "") (/\($r.path // ""))",
			text: "Page: https://biohackerwiki.com/\($r.locale // "en")/\($r.path // "")\nSubmitted: \($r.created // "")\nComment id: \($r.id)\n\n\($r.content // "")"
		}
		+ (if ($e | test("^[^@\\s<>,;]+@[^@\\s<>,;]+\\.[^@\\s<>,;]+$"))
			and ($e | ascii_downcase) != "noreply@biohackerwiki.com"
			then {reply_to: $e} else {} end)
	' >"$tmp/payload" || { log "payload build failed comment $id"; return 1; }

	# Key goes in via stdin so it never appears in argv or logs.
	code=$(printf 'Authorization: Bearer %s\n' "$key" | curl -sS --max-time 20 \
		-o "$tmp/resp" -w '%{http_code}' \
		-X POST https://api.resend.com/emails \
		-H @- -H 'Content-Type: application/json' \
		--data-binary @"$tmp/payload" 2>/dev/null) || :
	resend_id=$(jq -r '.id // empty' <"$tmp/resp" 2>/dev/null)
	rm -f "$tmp/resp"

	if [ "$code" != 200 ] || [ -z "$resend_id" ]; then
		log "send failed comment $id http ${code:-000}"
		return 1
	fi
	if ! q "INSERT INTO bw_relay_sent(comment_id, resend_id) VALUES ($id, :'rid') ON CONFLICT (comment_id) DO NOTHING" \
		-v rid="$resend_id" >/dev/null; then
		log "sent comment $id resend $resend_id but recording it failed"
		return 1
	fi
	log "sent comment $id resend $resend_id"
}

# status_one COMMENT_ID RESEND_ID: record Resend's last_event for one sent email.
status_one() {
	cid=$1
	rid=$2
	case $cid in ''|*[!0-9]*) return ;; esac
	case $rid in ''|*[!A-Za-z0-9-]*) log "bad resend id comment $cid"; return ;; esac

	code=$(printf 'Authorization: Bearer %s\n' "$key" | curl -sS --max-time 20 \
		-o "$tmp/resp" -w '%{http_code}' \
		-H @- "https://api.resend.com/emails/$rid" 2>/dev/null) || :
	ev=$(jq -r '.last_event // empty' <"$tmp/resp" 2>/dev/null)
	rm -f "$tmp/resp"
	[ "$code" = 200 ] || { log "status failed comment $cid http ${code:-000}"; return; }
	case $ev in ''|*[!A-Za-z_]*) return ;; esac

	changed=$(q "UPDATE bw_relay_sent SET last_event = :'ev'
WHERE comment_id = $cid AND last_event IS DISTINCT FROM :'ev' RETURNING comment_id" \
		-v ev="$ev") || { log "status update failed comment $cid"; return; }
	[ -n "$changed" ] && log "status comment $cid $ev"
}

run_once() {
	key=$(q "SELECT value->>'pass' FROM settings WHERE key = 'mail'") || { log "settings query failed"; return; }
	[ -n "$key" ] || { log "no Resend key in settings.mail.pass"; return; }

	rows=$(q "
SELECT json_build_object(
	'id', c.id, 'locale', p.\"localeCode\", 'path', p.path, 'title', p.title,
	'content', c.content, 'email', c.email, 'created', c.\"createdAt\")
FROM comments c JOIN pages p ON p.id = c.\"pageId\"
WHERE c.id > (SELECT v FROM bw_relay_state WHERE k = 'watermark')
	AND c.id NOT IN (SELECT comment_id FROM bw_relay_sent)
ORDER BY c.id
LIMIT 20") || { log "comments query failed"; return; }

	# json_build_object escapes newlines, so each row is exactly one line.
	if [ -n "$rows" ]; then
		printf '%s\n' "$rows" | while IFS= read -r row; do
			send_one "$row" || break
		done
	fi

	q "UPDATE bw_relay_state SET v = s.m FROM (SELECT max(comment_id) AS m FROM bw_relay_sent) s
WHERE k = 'watermark' AND s.m > v" >/dev/null || log "watermark update failed"

	pending=$(q "
SELECT comment_id, resend_id FROM bw_relay_sent
WHERE resend_id IS NOT NULL AND sent_at > now() - interval '1 day'
	AND (last_event IS NULL OR last_event IN ('sent', 'queued', 'scheduled', 'delivery_delayed'))
ORDER BY comment_id
LIMIT 5") || { log "status query failed"; return; }

	if [ -n "$pending" ]; then
		printf '%s\n' "$pending" | while IFS='|' read -r cid rid; do
			status_one "$cid" "$rid"
		done
	fi
}

while :; do
	run_once
	key=
	sleep "$RELAY_INTERVAL"
done
