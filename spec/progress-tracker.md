# Progress Tracker

Update this file after every meaningful implementation change.

## Completed

- **Parallel topic processing with promise-based dispatch** — Master agent (`agent.mbt`) fans out to child agents via `@api.create_promise()` + `@api.await_promise()`, counting successful `"Created lesson"` results
- **SurrealDB client rewrite** — `surreal_client.mbt`: env-based auth (`build_auth_header`), env-based ns/db, strict record ID validation (`is_valid_record_id`), JSON/SQL injection prevention (`json_escape`/`sql_escape`), normalized error handling (no `.unwrap()`)
- **Child agent identity fix** — Raw SurrealDB record IDs with backticks/colons blocked Golem agent ID parsing; switched to simple `child_0`–`child_N` names with topic ID as method parameter
- **Seed data alignment** — `test-setup.surql`: class names match topics (`Jss 1`/`Jss 2`), term `Noel Term` seeded, `has_subject` edges added for both class levels
- **Code quality** — Removed hardcoded credentials, fixed spawn-success tracking bug (`agent.mbt`), added `\b`/`\f` to JSON escaping, added `BAML_BASE_URL` env var, fixed `string_to_bytes` Unicode truncation

## In Progress

## Important Notes for Next Session


## Next Steps (Session Bootstrap)


## Recent Specs


## Open Questions

- None.

## Architecture Decisions


## Session Notes
