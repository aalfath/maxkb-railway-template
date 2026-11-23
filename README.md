# MaxKB on Railway

One-click Railway template for [MaxKB](https://github.com/1Panel-dev/MaxKB), the open-source platform for RAG knowledge bases and AI agents.

## What it deploys

| Service | Source | What it does |
|---|---|---|
| **MaxKB** | this repo, `maxkb/Dockerfile` (`1panel/maxkb:v2.10.9-lts`, pinned by digest) | Web UI and API on the public domain, the local embedding model server and the background task worker. Volume at `/opt/maxkb` (logs, extra Python packages, init scripts). |
| **Postgres** | Railway PostgreSQL (includes pgvector) | Users, applications, knowledge bases, document vectors and uploaded files. Volume. |
| **Redis** | Railway Redis | Cache, login sessions and the task queue. Volume. |

The PostgreSQL and Redis servers bundled inside the MaxKB image stay off.

## After deploy

1. Wait until the MaxKB service is healthy. The first deploy pulls a 1.3 GB image and runs the database migrations: allow about 5 minutes.
2. Open the MaxKB domain. You land on `/admin/login`.
3. Sign in as **`admin`** with the password in the MaxKB service's `MAXKB_DEFAULT_PASSWORD` variable, then change it when MaxKB asks you to.
4. Add a model provider under **Models** (OpenAI, Anthropic, DeepSeek, Gemini, Ollama and others), create a knowledge base and upload documents, then build an application or agent.

`MAXKB_DEFAULT_PASSWORD` is read once, when the database is first created. Changing the variable later doesn't change the stored password: change it in the UI. MaxKB asks for a captcha after a failed sign-in and locks the account for 10 minutes after 5.

## Variables

All are set by the template; the deploy form asks for nothing.

| Variable | Default | Purpose |
|---|---|---|
| `MAXKB_DEFAULT_PASSWORD` | `Mk1!` + 14 generated characters | First password of the `admin` account (upstream's public default is never used) |
| `MAXKB_SECRET_KEY` | generated, 64 characters | Signs login tokens; keep it stable so sessions survive restarts |
| `MAXKB_DB_*` | references to `Postgres` | Database host, port, name, user, password |
| `MAXKB_REDIS_*` | references to `Redis` | Redis host, port, password |
| `PORT` | `8080` | Port MaxKB listens on |

Optional, read by the start script if you add them: `MAXKB_CORE_WORKER` (web workers, default 1; 2–3 on bigger plans), `MAXKB_LANGUAGE_CODE` (default `en-US`; `zh-CN`, `zh-Hant`), `MAXKB_TIME_ZONE` (default `UTC`), `MAXKB_DB_MAX_OVERFLOW` (default 5). Any other `MAXKB_*` setting from upstream's docs works too.

## Resources

MaxKB runs three Python processes (web, local embedding model, task worker). It needs about **1.3 GB of RAM idle and 2 GB once the built-in embedding model has run**, so it doesn't fit Railway's Free or Trial plan (0.5 GB per service). Use the Hobby plan or higher. If MaxKB stops unexpectedly, the start script exits non-zero and Railway restarts the service.

## Notes

- The built-in embedding model (`text2vec-base-chinese`) is tuned for Chinese text. For English documents, add an embedding model from your provider under Models and pick it when you create a knowledge base.
- Tool code runs in upstream's sandbox. The template also blocks it from Railway's private network (`*.railway.internal` and private address ranges), so tools can't reach Postgres or Redis directly. Override with `MAXKB_SANDBOX_PYTHON_BANNED_HOSTS` if you need to.
- Back up the Postgres service (`pg_dump` over the TCP proxy). Uploaded files live in Postgres large objects, which `pg_dump` includes.

## Updates

The MaxKB service builds from this repo. When a new MaxKB release is pinned here (with an entry in [`CHANGELOG.md`](CHANGELOG.md), breaking changes first), Railway shows an update notice on your project, and you choose when to apply it. Migrations run automatically on start. Postgres and Redis are Railway's own services and are not changed by template updates.

## Licence

MaxKB is GPL-3.0 licensed by FIT2CLOUD. This repo only contains the Railway wrapper.
