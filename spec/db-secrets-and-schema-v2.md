# DB Secrets & Schema v2 Migration

## Goal

Migrate both MoonBit (content) and Rust (PDF) Golem agents from hardcoded SurrealDB credentials and flat `lesson_content` table to Golem-managed secrets and the normalized graph schema (`class_levels`, `subjects`, `terms`, `has_subject`, `lessons`), using SurrealDB's native graph traversal and ACID transactions.

---

## Design

### Secrets Strategy

All five SurrealDB connection parameters stored as Golem secrets, injected via typed config at agent construction:

| Secret | Type | MoonBit Field | Rust Field |
|--------|------|---------------|------------|
| SurrealDB URL | `Secret[String]` | `db_url` | `db_url` |
| Username | `Secret[String]` | `db_username` | `db_username` |
| Password | `Secret[String]` | `db_password` | `db_password` |
| Namespace | `Secret[String]` | `db_namespace` | `db_namespace` |
| Database name | `Secret[String]` | `db_name` | `db_name` |

Secrets are shared between both components — same names, same CLI commands.

Basic auth header is built **at runtime** from `base64(username + ":" + password)` instead of the current hardcoded base64 token.

### Schema Access Pattern

- **Reads** (`fetch_lessons`): Graph traversal via `class_subject.in.name`, `class_subject.out.name`, `term.name` with `AS` aliasing to keep existing struct shapes unchanged
- **Writes** (`create_row`): Single SurrealDB `BEGIN TRANSACTION...COMMIT TRANSACTION` batch that resolves record IDs, implicitly creates `has_subject` edges if missing, then creates the `lessons` record
- **Topics** (`fetch_topics`): Unchanged — reads from separate schedule table with no schema change

### Config Flow

```
MasterContentAgent(config: @config.Config[DbConfig])
  └─ generate_all()
      └─ ChildContentAgent.scoped("c_{id}", fn(c) { c.trigger_generate(table, id) }, config)
          └─ ChildContentAgent(config)
              └─ uses config for fetch_topics, call_baml, create_row

PdfAgent(subject, class, mode, config: Config<DbConfig>)
  └─ pdf_generator()
      └─ fetch_lessons(subject, class, config)
      └─ pdf_engine(lessons, subject, class, mode)
```

Both agents receive the same `DbConfig` shape but via their respective SDK's config mechanism.

---

## Implementation

### 1. MoonBit — New file `components-moonbit/db_config.mbt`

Create config struct with all five secrets:

```moonbit
///|
/// SurrealDB connection configuration (all fields are secrets)
#derive.config
pub(all) struct DbConfig {
  db_url : @config.Secret[String]
  db_username : @config.Secret[String]
  db_password : @config.Secret[String]
  db_namespace : @config.Secret[String]
  db_name : @config.Secret[String]
}
```

### 2. MoonBit — Update `components-moonbit/moon.pkg`

Add these imports to the existing import block:

```moonbit
"golemcloud/golem_sdk/config" @config,
"moonbitlang/core/encoding/base64" @base64,
```

### 3. MoonBit — Rewrite `components-moonbit/surreal_client.mkt`

#### 3a. `db_request` — accept config, build auth at runtime

```moonbit
pub fn db_request(query : String, config : DbConfig) -> Result[String, AgentError] {
  let url = config.db_url.get!()
  let username = config.db_username.get!()
  let password = config.db_password.get!()
  let ns = config.db_namespace.get!()
  let db_name_val = config.db_name.get!()

  let (scheme, authority, path) = parse_db_url(url)
  let creds = username + ":" + password
  let encoded = @base64.encode(@utf8.encode(creds))
  let auth_value = "Basic " + encoded

  let headers = @wasiTypes.Fields::from_list([
    ("Accept", str_to_bytes("application/json")),
    ("Authorization", str_to_bytes(auth_value)),
    ("NS", str_to_bytes(ns)),
    ("DB", str_to_bytes(db_name_val)),
  ]).unwrap()

  // ... rest of HTTP request unchanged ...
}
```

Replace the current hardcoded auth header and env-var-based URL/NS/DB with the secret values. Also add `NS` and `DB` headers to every request (SurrealDB HTTP API requires these when not using `USE` in every query, but we'll keep `USE` in multi-statement batches for clarity).

#### 3b. `fetch_topics` — unchanged

Signature stays `pub fn fetch_topics(table : String, config : DbConfig) -> Result[Array[TopicRecord], AgentError]`. No schema change needed — reads from the schedule table.

Update internal `db_request` calls to pass `config`.

#### 3c. `create_row` — new schema with transaction

```moonbit
pub fn create_row(
  content : CompleteLessonContent,
  source_id : String,
  config : DbConfig,
) -> Result[String, AgentError] {
  // Extract class/subject/term from content (same enum→string conversion as current)
  let class_str = class_level_to_str(content.class_level)
  let subject_str = content.subject
  let term_str = term_to_str(content.term)
  let ns = config.db_namespace.get!()
  let db_name_val = config.db_name.get!()

  // Build lesson JSON for all content fields
  // (same pattern as current, but mapped to lessons table fields)
  let json_str = build_lesson_json(content, source_id)

  let query = "USE NS " + ns + " DB " + db_name_val + ";\n" +
    "BEGIN TRANSACTION;\n" +
    "  LET $cl = (SELECT VALUE id FROM class_levels WHERE name = \"" + class_str + "\" LIMIT 1);\n" +
    "  LET $sub = (SELECT VALUE id FROM subjects WHERE name = \"" + subject_str + "\" LIMIT 1);\n" +
    "  LET $hs = (SELECT VALUE id FROM has_subject WHERE in = $cl AND out = $sub LIMIT 1);\n" +
    "  IF $hs == NONE {\n" +
    "    CREATE has_subject CONTENT { in: $cl, out: $sub, active: true };\n" +
    "  };\n" +
    "  LET $hs = (SELECT VALUE id FROM has_subject WHERE in = $cl AND out = $sub LIMIT 1);\n" +
    "  LET $t = (SELECT VALUE id FROM terms WHERE name = \"" + term_str + "\" LIMIT 1);\n" +
    "  CREATE lessons CONTENT " + json_str + ";\n" +
    "COMMIT TRANSACTION;"

  let _response = db_request(query, config)?
  Ok("Created: " + source_id)
}
```

The `build_lesson_json` function produces the `lessons` table content with `class_subject: $hs, term: $t` as record links, plus all content/array/string fields mapped from `CompleteLessonContent`.

#### 3d. `content_exists` — check new schema

```moonbit
pub fn content_exists(source_id : String, config : DbConfig) -> Bool {
  // source_id encodes class+subject+term+week to check for duplicates
  // Query: SELECT VALUE count() FROM lessons
  //        WHERE class_subject.in.name = $class
  //          AND class_subject.out.name = $subject
  //          AND term.name = $term AND week = $week;
  // Return count > 0
}
```

#### 3e. `fetch_lessons` — graph traversal for PDF agent use (if MoonBit side needs it)

Keep as a stub or implement with graph traversal query on `lessons` table.

### 4. MoonBit — Update `components-moonbit/agent.mbt`

```moonbit
#derive.agent
#derive.mount("/content")
struct MasterContentAgent {
  config : @config.Config[DbConfig]
}

fn MasterContentAgent::new(config : @config.Config[DbConfig]) -> MasterContentAgent {
  { config, }
}
```

In `generate_all`, pass config to child agent via scoped callback:

```moonbit
let cb = fn(c : ChildContentAgentClient) -> Unit raise @common.AgentError {
  c.trigger_generate(table_name, id)
}
let _ = ChildContentAgentClient::scoped(child_name, cb, self.config) catch { _ => () }
```

### 5. MoonBit — Update `components-moonbit/child_agent.mbt`

```moonbit
#derive.agent
struct ChildContentAgent {
  id : String
  config : @config.Config[DbConfig]
}

fn ChildContentAgent::new(id : String, config : @config.Config[DbConfig]) -> ChildContentAgent {
  { id, config, }
}
```

In `generate`, pass `self.config.value` to `fetch_topics`, `call_baml_generate_lesson`, and `create_row`.

### 6. Rust — Update `components-rust/Cargo.toml`

```toml
base64 = "0.22"
```

### 7. Rust — Update `components-rust/src/lib.rs`

#### 7a. Add DbConfig struct

```rust
#[derive(ConfigSchema)]
pub struct DbConfig {
    #[config_schema(secret)]
    pub db_url: Secret<String>,
    #[config_schema(secret)]
    pub db_username: Secret<String>,
    #[config_schema(secret)]
    pub db_password: Secret<String>,
    #[config_schema(secret)]
    pub db_namespace: Secret<String>,
    #[config_schema(secret)]
    pub db_name: Secret<String>,
}
```

#### 7b. Update PdfAgent trait and implementation

```rust
#[agent_definition(ephemeral, mount = "/generate-pdf-api/{subject}/{class}/{mode}")]
pub trait PdfAgent {
    fn new(subject: String, class: String, mode: String, #[agent_config] config: Config<DbConfig>) -> Self;
    #[endpoint(get = "/")]
    async fn pdf_generator(&mut self) -> UnstructuredBinary<String>;
}

pub struct PdfImpl {
    subject: String,
    class: String,
    mode: String,
    config: Config<DbConfig>,
}

#[agent_implementation]
impl PdfAgent for PdfImpl {
    fn new(subject: String, class: String, mode: String, #[agent_config] config: Config<DbConfig>) -> Self {
        Self { subject, class, mode, config }
    }
    // ...
}
```

#### 7c. Update fetch_lessons

Replace the current `lesson_content` query with graph traversal on `lessons`:

```surql
SELECT
  topic_title,
  class_subject.in.name AS class_level,
  class_subject.out.name AS subject,
  term.name AS term,
  week AS week,
  duration_mins AS duration_mins,
  introduction, conclusion, teacher_tips,
  remediation, formative_assessment, summative_assessment,
  objectives, content_sections, key_points, lesson_steps,
  mcq_questions, theoretical_questions,
  materials, prior_knowledge, success_criteria,
  extension_activities, textbook_references,
  primary_sources
FROM lessons
WHERE class_subject.in.name = "$class"
  AND class_subject.out.name = "$subject"
ORDER BY term.sort_order ASC, week ASC;
```

Use secret values for NS and DB name instead of env vars. Build Basic auth at runtime:

```rust
let creds = format!("{}:{}", config.db_username.get(), config.db_password.get());
let encoded = general_purpose::STANDARD.encode(creds.as_bytes());
let auth_value = format!("Basic {}", encoded);
```

Remove env-var-based `SURREAL_DB_URL` reading. Change `db_request` to accept `&DbConfig`.

### 8. Update `golem.yaml`

Add `secretDefaults` and remove env vars for DB:

```yaml
components:
  components:rust:
    dir: "components-rust"
    templates: rust
    # SURREAL_DB_URL removed — replaced by secrets
    files:
      - sourcePath: ./components-rust/files/template.typ
        targetPath: /templates/template.typ
      - sourcePath: ./components-rust/files/times.ttf
        targetPath: /fonts/times-new-roman.ttf
      - sourcePath: ./components-rust/files/watermark.png
        targetPath: /templates/images/watermark.png

  components:moonbit:
    dir: "components-moonbit"
    templates: my-moonbit
    # SURREAL_DB_URL removed — replaced by secrets
    env:
      BAML_BASE_URL: "{{ BAML_BASE_URL }}"

secretDefaults:
  local:
    dbUrl: "http://localhost:8000"
    dbUsername: "golem"
    dbPassword: "dev-password"
    dbNamespace: "main"
    dbName: "johnethel-school-generated-lessons"
```

### 9. Regenerate tooling

```bash
moon info && moon fmt
golem build
```

---

## Dependencies

| Package | Component | Version | Source |
|---------|-----------|---------|--------|
| `moonbitlang/core/encoding/base64` (as `@base64`) | MoonBit | Core (toolchain) | Add to `moon.pkg` imports |
| `golemcloud/golem_sdk/config` (as `@config`) | MoonBit | 0.5.2 | Already in project, add to `moon.pkg` imports |
| `base64` | Rust | 0.22 | `cargo add base64` in `components-rust/` |

No mooncake dependencies need to be added to `moon.mod.json` — `moonbitlang/core` is the built-in standard library, and `golemcloud/golem_sdk/config` is part of the existing SDK.

---

## Verification Checklist

- [ ] `moon check --target wasm` passes with no errors (MoonBit component)
- [ ] `cargo check --target wasm32-wasip2` passes in `components-rust/` (Rust component)
- [ ] `golem build` completes successfully for both components
- [ ] No hardcoded credentials or base64 tokens remain in any source file
- [ ] `golem secret create` works for all 5 secrets in local environment
- [ ] Agent starts and connects to SurrealDB without env vars or hardcoded auth
- [ ] Basic auth header is correctly base64-encoded from `username:password`
- [ ] `fetch_lessons` returns lessons with correct `class_level`, `subject`, `term` string values (graph traversal resolves correctly via `class_subject.in.name` / `class_subject.out.name` / `term.name`)
- [ ] `create_row` creates lesson in `lessons` table within a single ACID transaction
- [ ] `create_row` implicitly creates `has_subject` edge when class+subject pair doesn't exist yet
- [ ] `create_row` rolls back on error (no orphaned `has_subject` edge without a lesson)
- [ ] `MasterContentAgent.generate_all` dispatches child agents successfully with config
- [ ] `ChildContentAgent.generate` passes config through to `db_request`, `fetch_topics`, `create_row`
- [ ] `PdfAgent.pdf_generator` returns valid PDF using secret-based DB connection
- [ ] `golem agent invoke` works for both agents with the new config
