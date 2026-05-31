# Parallel Topic Generation with Golem Promises

## Goal

Replace the current fire-and-forget fan-out with a promise-based parallel execution engine that reads unprocessed topics from a fixed `topics` table, dispatches all of them as fire-and-forget child agents, and durably awaits their results. The `generated` field on each topic record is set to `true` atomically with lesson creation to guarantee idempotency.

---

## Design

### Visual Flow

```
HTTP GET /content/generate  (no query params)
  │
  ▼
MasterContentAgent::generate_all()       ← DURABLE orchestrator
  │
  ├─ fetch_topics(config)                → SELECT * FROM topics WHERE generated = false;
  │                                        (all unprocessed topics, no LIMIT)
  │
  ├─ for each topic:
  │     promise_ids.push(@api.create_promise())
  │     child_name = "c_" + topic.id
  │     ChildContentAgentClient::scoped(child_name, fn(c) {
  │       c.trigger_generate(promise_id)
  │     })                                ← all children fire near-simultaneously
  │
  ├─ for each promise_id:                ← await IN ORDER
  │     bytes = @api.await_promise(pid)   ← durably suspends parent
  │     @logging.info(String::from_array(bytes...))
  │
  └─ return "N topics processed"

Each child agent (durable, identified by topic ULID):
  │
  ├─ sleep_ms(4000)                      ← rate-limit stagger
  ├─ fetch_topic_by_id(self.id, config)  → SELECT * FROM topics WHERE id = <ulid>
  │                                        (single targeted query, skips if already generated)
  │
  ├─ request = convert_topic_to_request(topic)
  ├─ content = call_baml_generate_lesson(request)
  │   (on failure → complete_promise("BAML error: ..."), return)
  │
  ├─ create_row(content, self.id, config)
  │   ┌─ BEGIN TRANSACTION;
  │   │   ...resolve $cl, $sub, $hs, $t...
  │   │   CREATE lessons CONTENT { class_subject: $hs, term: $t, ... };
  │   │   UPDATE type::thing("topics", <ulid>) SET generated = true;  ← ATOMIC
  │   └─ COMMIT TRANSACTION;
  │
  └─ @api.complete_promise(promise_id, payload_bytes)
```

### Key Decisions

| Decision | Rationale |
|----------|-----------|
| **No chunking** | All children dispatched at once. Parent awaits promises sequentially. Total time ≈ max(child_time) + O(N) replay overhead. No manual batching needed since children are durable and auto-retry. |
| **Child agents are DURABLE** | If a child crashes mid-execution, Golem replays from the oplog. Recorded I/O results (BAML HTTP call, DB transaction) are returned without re-execution. The promise always gets completed. An ephemeral child that crashes would hang the parent forever on `await_promise`. |
| **Master agent is DURABLE** | Must persist the promise ID array and `await_promise` suspension points. If the parent crashes while waiting, it resumes from the oplog — already-fulfilled promises return their value immediately, pending ones re-suspend. |
| **`generated = true` inside the same ACID transaction** | Atomic with lesson creation. No split-brain: if the transaction commits, both the lesson exists AND the topic is marked done. On Golem replay, the recorded DB response is returned without re-executing. |
| **Child re-checks `generated` before processing** | Belt-and-suspenders guard. Query includes `AND generated = false`, so on Golem replay the child sees an empty result and skips if the topic was already processed in a prior (successful) run. |
| **ULID IDs as strings** | SurrealDB returns `id` as a plain JSON string. Compatible with current `fetch_topics` parser. UPDATE in SurrealQL uses `UPDATE type::thing("topics", <ulid>) SET generated = true`. |
| **Error → always complete_promise** | The child MUST complete the promise in ALL paths (success, BAML error, DB error, skip). Otherwise the parent hangs forever on `await_promise`. |

---

## Implementation

### 1. `agent.mbt` — MasterContentAgent

**Current endpoint + signature:**
```moonbit
#derive.mount("/content")
#derive.endpoint(get="/generate?table={table_name}")
pub fn MasterContentAgent::generate_all(self, table_name: String) -> Result[String, AgentError]
```

**New:**
```moonbit
#derive.mount("/content")
#derive.endpoint(get="/generate")
pub fn MasterContentAgent::generate_all(self) -> Result[String, AgentError]
```

**Body (pseudocode):**
```
1. config = self.config.value
2. topics = fetch_topics(config)   // no table param
3. promise_ids: Array[@rpcTypes.PromiseId] = []
4. for t in topics:
     match t.id {
       Some(ulid) => {
         let pid = @api.create_promise()
         promise_ids.push(pid)
         let child_name = "c_" + ulid
         let _ = ChildContentAgentClient::scoped(child_name, fn(c) raise @common.AgentError {
           c.trigger_generate(pid)
         }) catch { _ => () }
       }
       None => continue
     }
5. for pid in promise_ids:
     let bytes = @api.await_promise(pid)
     let msg = String::from_array(bytes.to_array().map(fn(b) { Char::from_int(b.to_int()) }))
     @logging.info(msg)
6. Ok(topics.length().to_string() + " topics processed")
```

**Changes from current:**
- Remove `table_name` parameter from method and endpoint annotation
- Remove hardcoded fallback topic records (or keep minimal fallback returning `Ok([])`)
- Replace fire-and-forget loop with promise creation + trigger + await pattern
- Pass `promise_id` instead of `table_name, row_id` to child

### 2. `child_agent.mbt` — ChildContentAgent

**Current method:**
```moonbit
pub fn ChildContentAgent::generate(self, table: String, row_id: String) -> Unit
```

**New:**
```moonbit
pub fn ChildContentAgent::generate(self, promise_id: @rpcTypes.PromiseId) -> Unit
```

**Body:**
```moonbit
pub fn ChildContentAgent::generate(self, promise_id : @rpcTypes.PromiseId) -> Unit {
  sleep_ms(4000)
  let config = self.config.value

  let topic = match fetch_topic_by_id(self.id, config) {
    Ok(Some(t)) => t
    Ok(None) => {
      let _ = @api.complete_promise(promise_id, str_to_bytes("skipped: not found or already generated"))
      return
    }
    Err(e) => {
      let _ = @api.complete_promise(promise_id, str_to_bytes("db error: " + e.message))
      return
    }
  }

  let request = convert_topic_to_request(topic)
  @logging.info("calling BAML for: " + topic.topic)
  let content = match call_baml_generate_lesson(request) {
    Ok(c) => c
    Err(e) => {
      @logging.error("BAML failed: " + e.message)
      let _ = @api.complete_promise(promise_id, str_to_bytes("BAML error: " + e.message))
      return
    }
  }
  @logging.info("BAML OK: " + content.topic_title)

  @logging.info("writing to DB: " + content.topic_title)
  let result = create_row(content, self.id, config)
  match result {
    Ok(msg) => {
      let _ = @api.complete_promise(promise_id, str_to_bytes(msg))
      @logging.info("DB OK: " + msg)
    }
    Err(e) => {
      let _ = @api.complete_promise(promise_id, str_to_bytes("DB error: " + e.message))
      @logging.error("DB error: " + e.message)
    }
  }
}
```

**Helper conversion function (add to `child_agent.mbt` or `surreal_client.mbt`):**
```moonbit
fn str_to_bytes(s : String) -> Bytes {
  Bytes::from_array(s.to_array().map(fn(c) { c.to_int().to_byte() }))
}
```

**Changes from current:**
- Remove `table`, `row_id` params; add `promise_id` param
- Replace `fetch_topics(table, config) + find_topic(topics, row_id)` with single `fetch_topic_by_id(self.id, config)` call
- Complete promise on every exit path (success, BAML error, DB error, skip)
- Add `str_to_bytes` helper (already exists as a variant in `surreal_client.mbt` — may reuse)

### 3. `surreal_client.mbt` — DB layer

#### 3a. `fetch_topics` — remove table param, add generated filter

```moonbit
pub fn fetch_topics(config : DbConfig) -> Result[Array[TopicRecord], AgentError] {
  let ns = config.db_namespace.get() catch { ... }
  let db_name_val = config.db_name.get() catch { ... }
  let query = "USE NS " + ns + " DB " + db_name_val + "; SELECT * FROM topics WHERE generated = false;"
  // rest unchanged: db_request → JSON parse → filter_map → Ok(records)
}
```

#### 3b. `fetch_topic_by_id` — new function (single targeted query)

```moonbit
pub fn fetch_topic_by_id(
  topic_id : String,
  config : DbConfig,
) -> Result[TopicRecord?, AgentError] {
  let ns = config.db_namespace.get() catch { ... }
  let db_name_val = config.db_name.get() catch { ... }
  let query = "USE NS " + ns + " DB " + db_name_val +
    "; SELECT * FROM " + topic_id + ";"
  let response = match db_request(query, config) { ... }
  // Parse JSON, extract first record, return Ok(Some(record)) or Ok(None)
}
```

If SurrealQL `SELECT * FROM <record_id>` works with string-format ULIDs, use the raw `topic_id` directly. If not, use `SELECT * FROM topics WHERE id = " + json_escape(topic_id) + " AND generated = false;`.

#### 3c. `create_row` — remove source_id, add generated = true in transaction

```moonbit
pub fn create_row(
  content : CompleteLessonContent,
  topic_id : String,
  config : DbConfig,
) -> Result[String, AgentError] {
  let class_str = class_level_to_str(content.class_level)
  let term_str = term_to_str(content.term)
  let ns = config.db_namespace.get() catch { ... }
  let db_name_val = config.db_name.get() catch { ... }

  let content_json = build_lesson_json(content)

  let query = "USE NS " + ns + " DB " + db_name_val + ";\n" +
    "BEGIN TRANSACTION;\n" +
    "  LET $cl = (SELECT VALUE id FROM class_levels WHERE name = " + json_escape(class_str) + " LIMIT 1);\n" +
    "  LET $sub = (SELECT VALUE id FROM subjects WHERE name = " + json_escape(content.subject) + " LIMIT 1);\n" +
    "  LET $hs = (SELECT VALUE id FROM has_subject WHERE in = $cl AND out = $sub LIMIT 1);\n" +
    "  IF $hs == NONE {\n" +
    "    RELATE $cl -> has_subject -> $sub CONTENT { active: true };\n" +
    "  };\n" +
    "  LET $hs = (SELECT VALUE id FROM has_subject WHERE in = $cl AND out = $sub LIMIT 1);\n" +
    "  LET $t = (SELECT VALUE id FROM terms WHERE name = " + json_escape(term_str) + " LIMIT 1);\n" +
    "  CREATE lessons CONTENT " + content_json + ";\n" +
    "  UPDATE type::thing(\"topics\", " + json_escape(topic_id) + ") SET generated = true;\n" +
    "COMMIT TRANSACTION;"

  let _response = match db_request(query, config) { ... }
  Ok("Created lesson for topic: " + topic_id)
}
```

#### 3d. `build_lesson_json` — remove source_id param

```moonbit
fn build_lesson_json(content : CompleteLessonContent) -> String {
  // Same body as now, just remove the _source_id parameter
}
```

#### 3e. `content_exists` — remove entirely

No longer needed. The `generated` field on the `topics` table provides idempotency.

### 4. `moon.pkg` — Imports

No changes needed. The following are already imported:
- `@api` (line 19) — for `create_promise`, `await_promise`, `complete_promise`
- `@rpcTypes` (line 11, `golemcloud/golem_sdk/interface/golem/core/types`) — for `PromiseId`

### 5. `golem.yaml`

No changes needed. Secrets, env vars, and build commands stay exactly as they are.

---

## Dependencies

None. All required packages are already imported:
- `@api` (`golemcloud/golem_sdk/api`) — promises: `create_promise`, `await_promise`, `complete_promise`
- `@rpcTypes` (`golemcloud/golem_sdk/interface/golem/core/types`) — `PromiseId` type

---

## Verification Checklist

- [ ] `moon check --target wasm` passes with 0 errors in `components-moonbit/`
- [ ] `golem build` passes for both components
- [ ] `fetch_topics(config)` reads only topics with `generated = false`
- [ ] `fetch_topic_by_id(id, config)` returns `None` if topic not found or already generated
- [ ] `create_row(content, topic_id, config)` includes `UPDATE type::thing("topics", "<topic_id>") SET generated = true;` inside the transaction
- [ ] `create_row` no longer accepts or uses `source_id`
- [ ] `build_lesson_json(content)` no longer accepts `_source_id`
- [ ] `content_exists` is removed from `surreal_client.mbt`
- [ ] Master agent creates N promises for N topics via `@api.create_promise()`
- [ ] Master agent fires all children via `trigger_generate(promise_id)` (no `table`/`row_id` params)
- [ ] Master agent awaits all promises, logging each result
- [ ] Child agent reads topic from `self.id`, no `table`/`row_id` params
- [ ] Child agent completes promise on ALL paths (success, BAML error, DB error, skip)
- [ ] Child agent's fetch query includes `AND generated = false` guard
- [ ] `@api.complete_promise` is called on every exit path — no uncompleted promises, no hung parent
- [ ] No hardcoded credentials remain in any source file
- [ ] Both agents have explicit `#derive.agent` annotation (durable default)
