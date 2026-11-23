# Changelog

Each entry is one version of this Railway template. Breaking changes are listed first.

## v2.10.9-lts (2026-11-23)

First release of the template.

- MaxKB `v2.10.9-lts` (`1panel/maxkb:v2.10.9-lts@sha256:97810f4263ae95606322aa5786d6efc50891a7bccb7536368f04988d517f2701`).
- Three services: MaxKB (built from this repo, volume `/opt/maxkb`), Railway Postgres (pgvector) and Railway Redis.
- The admin password is generated at deploy time; the public upstream default `MaxKB@123..` is never used.
- Start script: waits for Postgres, enables `vector`, runs migrations under a lock, sizes workers for a small container, sends MaxKB's logs to Railway, and exits non-zero when MaxKB stops, so Railway restarts it.
