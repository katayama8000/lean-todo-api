# Lean Todo API

A JSON todo API built with Lean 4, the standard HTTP server, and SQLite. See [design.md](design.md) for the architecture and trade-offs.

## Run

Requires Docker with Docker Compose and Make. The build supplies Lean and SQLite in containers.

```sh
make up
curl -fsS http://127.0.0.1:8080/health
```

Set `TODO_HOST_PORT` before running Make if port 8080 is taken. `make logs` streams the server logs. `make down` stops the service and retains the SQLite volume.

## API

| Method | Path | Request JSON | Success |
| --- | --- | --- | --- |
| GET | `/health` | | `200` |
| GET | `/todos` | | `200`, array sorted by ID |
| POST | `/todos` | `{"title":"Write a test"}` | `201`, todo and `Location` |
| GET | `/todos/{id}` | | `200`, todo |
| PUT | `/todos/{id}` | `{"title":"Write a test","completed":true}` | `200`, updated todo |
| DELETE | `/todos/{id}` | | `204` |

```sh
curl -fsS http://127.0.0.1:8080/todos \
  -H 'Content-Type: application/json' \
  -d '{"title":"Write a test"}'
```

A todo has `id`, `title`, and `completed`. Create defaults to incomplete. PUT replaces both writable fields. The app binds to localhost through Compose and is intended for local use.

## Verify

Run `make test` with Python 3 on the host. The test uses Docker Compose for the API and SQLite, checks HTTP responses and volume persistence, and cleans up its own project and volume.
