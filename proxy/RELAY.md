# Correction relay

`relay.sh` runs in the background of the proxy container (started by `start.sh`, caddy stays in
the foreground). Every `RELAY_INTERVAL` seconds it reads new Wiki.js v2 comments (correction
submissions) from the wiki database and emails each one to the corrections inbox through the
Resend HTTP API. The Resend API key is read fresh each loop from the Wiki.js mail settings
(`settings.value->>'pass'` where `key = 'mail'`) and is never logged.

If the relay crashes, `start.sh` restarts it after 30 seconds. It never stops caddy.

## Env vars

| var | default | notes |
|---|---|---|
| `RELAY_DB_HOST` | (none) | empty disables the relay |
| `RELAY_DB_PORT` | `5432` | |
| `RELAY_DB_NAME` | (none) | Wiki.js database |
| `RELAY_DB_USER` | (none) | |
| `RELAY_DB_PASS` | (none) | empty disables the relay |
| `RELAY_TO` | `corrections@biohackerwiki.com` | |
| `RELAY_FROM` | `Biohacker Wiki <noreply@biohackerwiki.com>` | must be a Resend-verified domain |
| `RELAY_INTERVAL` | `60` | seconds between polls |

When disabled it logs `relay disabled` and sleeps forever.

## Tables (created in the Wiki.js database on start)

- `bw_relay_sent(comment_id, sent_at, resend_id, last_event)`: one row per comment emailed.
  `last_event` is Resend's delivery status (e.g. `delivered`, `bounced`), polled each loop for up to
  5 emails from the last day that are still unset or in flight; changes log `status comment <id> <event>`.
- `bw_relay_state(k, v)`: `watermark` row. Only comments with `id > watermark` are considered.
  On first start it is set to the current max comment id, so existing comments are never emailed.
  After each batch it moves up to the highest sent comment id.

Each loop sends at most 20 comments in id order and stops the batch at the first failure, so a
failed comment is retried next loop and nothing after it is skipped. A reply-to header is set to
the submitter's email when it looks valid and is not the noreply address.

## Logs

`relay: sent comment <id> resend <resend_id>` or `relay: send failed comment <id> http <code>`.

## Reset and maintenance

Run against the Wiki.js database:

- Resend a comment: `DELETE FROM bw_relay_sent WHERE comment_id = <id>;` and
  `UPDATE bw_relay_state SET v = <id> - 1 WHERE k = 'watermark';`
- Skip a comment that keeps failing: `INSERT INTO bw_relay_sent(comment_id) VALUES (<id>);`
- Start over from "now" (no backlog): `DELETE FROM bw_relay_state WHERE k = 'watermark';` then
  restart the proxy service; the watermark is reinitialized to the current max comment id.
- Remove completely: `DROP TABLE bw_relay_sent, bw_relay_state;` and unset `RELAY_DB_HOST`.
