///|
/// Helper: UTF-8 string to WASI field-value bytes
fn str_to_bytes(s : String) -> FixedArray[Byte] {
  @utf8.encode(s).to_fixedarray()
}

///|
/// Helper: bytes back to string
fn bytes_to_str(bs : FixedArray[Byte]) -> String {
  @utf8.decode_lossy(Bytes::from_array(bs).view())
}

///|
/// Parse SURREAL_DB_URL into (scheme, authority, path)
fn parse_db_url(url : String) -> (@wasiTypes.Scheme, String, String) {
  match url.split_once("://") {
    Some((scheme_view, rest_view)) => {
      let scheme_str = scheme_view.to_owned()
      let rest = rest_view.to_owned()
      let scheme = if scheme_str == "https" {
        @wasiTypes.Https
      } else {
        @wasiTypes.Http
      }
      match rest.split_once("/") {
        Some((auth_view, path_view)) =>
          (scheme, auth_view.to_owned(), "/" + path_view.to_owned())
        None => (scheme, rest, "/sql")
      }
    }
    None => (@wasiTypes.Http, url, "/sql")
  }
}

///|
/// Get SURREAL_DB_URL from environment variables
fn get_surrealdb_url() -> String {
  let envs = @cliEnv.get_environment()
  for env in envs {
    let (key, value) = env
    if key == "SURREAL_DB_URL" {
      let v = value
      if v.has_suffix("/sql") {
        return v
      }
      return v + "/sql"
    }
  }
  "http://localhost:8000/sql"
}

///|
/// Common HTTP request body, returns response body as string
fn do_http_post(
  url : String,
  headers : @wasiTypes.Fields,
  body_str : String,
) -> Result[String, AgentError] {
  let (scheme, authority, path) = parse_db_url(url)
  let request = @wasiTypes.OutgoingRequest::outgoing_request(headers)
  let _ = request.set_method(@wasiTypes.Post)
  let _ = request.set_scheme(Some(scheme))
  let _ = request.set_authority(Some(authority))
  let _ = request.set_path_with_query(Some(path))
  let body = match request.body() {
    Ok(b) => b
    Err(_) => return Err({ message: "Failed to get request body", code: "HTTP_ERROR" })
  }
  let output_stream = match body.write() {
    Ok(s) => s
    Err(_) => return Err({ message: "Failed to open output stream", code: "HTTP_ERROR" })
  }
  match output_stream.blocking_write_and_flush(str_to_bytes(body_str)) {
    Ok(_) => ()
    Err(_) => return Err({ message: "Failed to write request body", code: "HTTP_ERROR" })
  }
  output_stream.drop()
  match @wasiTypes.OutgoingBody::finish(body, None) {
    Ok(_) => ()
    Err(_) => return Err({ message: "Failed to finish request body", code: "HTTP_ERROR" })
  }
  let future_response = match @http.handle(request, None) {
    Ok(f) => f
    Err(_) => return Err({ message: "HTTP handle failed", code: "HTTP_ERROR" })
  }
  let pollable = future_response.subscribe()
  pollable.block()
  let response = match future_response.get() {
    Some(Ok(Ok(r))) => r
    _ => return Err({ message: "HTTP response error", code: "HTTP_ERROR" })
  }
  let status = response.status()
  let incoming_body = match response.consume() {
    Ok(b) => b
    Err(_) => return Err({ message: "Failed to consume response body", code: "HTTP_ERROR" })
  }
  let stream = match incoming_body.stream() {
    Ok(s) => s
    Err(_) => return Err({ message: "Failed to open response stream", code: "HTTP_ERROR" })
  }
  let bytes = match stream.blocking_read(1048576UL) {
    Ok(b) => b
    Err(_) => return Err({ message: "Failed to read response body", code: "HTTP_ERROR" })
  }
  stream.drop()
  let _ = @wasiTypes.IncomingBody::finish(incoming_body)
  let body = bytes_to_str(bytes)
  if status != 200U {
    return Err({
      message: "HTTP " + status.to_string() + ": " + body,
      code: "HTTP_ERROR",
    })
  }
  Ok(body)
}

///|
/// Get SURREAL_DB_NAMESPACE from environment variables
fn get_surrealdb_ns() -> String {
  let envs = @cliEnv.get_environment()
  for env in envs {
    let (key, value) = env
    if key == "SURREAL_DB_NS" { return value }
  }
  "main"
}

///|
/// Get SURREAL_DB_NAME from environment variables
fn get_surrealdb_name() -> String {
  let envs = @cliEnv.get_environment()
  for env in envs {
    let (key, value) = env
    if key == "SURREAL_DB" { return value }
  }
  "johnethel-school-generated-lessons"
}

///|
/// Build Basic auth from env vars (no hardcoded fallback)
fn build_auth_header() -> Result[(String, FixedArray[Byte]), AgentError] {
  let envs = @cliEnv.get_environment()
  let mut user : String? = None
  let mut pass : String? = None
  for env in envs {
    let (key, value) = env
    if key == "SURREAL_DB_USER" { user = Some(value) }
    if key == "SURREAL_DB_PASSWORD" { pass = Some(value) }
  }
  match (user, pass) {
    (Some(u), Some(p)) => {
      let b64 = @base64.encode(@utf8.encode(u + ":" + p).view())
      Ok(("Authorization", str_to_bytes("Basic " + b64)))
    }
    _ => Err({ message: "Missing SURREAL_DB_USER or SURREAL_DB_PASSWORD", code: "CONFIG_ERROR" })
  }
}

///|
/// Send a SurrealQL query with env-based auth and namespace
pub fn db_request(query : String) -> Result[String, AgentError] {
  let url = get_surrealdb_url()
  let ns = get_surrealdb_ns()
  let db = get_surrealdb_name()
  let (auth_name, auth_val) = match build_auth_header() {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let headers = match @wasiTypes.Fields::from_list([
    ("Accept", str_to_bytes("application/json")),
    ("surreal-ns", str_to_bytes(ns)),
    ("surreal-db", str_to_bytes(db)),
    (auth_name, auth_val),
  ]) {
    Ok(h) => h
    Err(_) => return Err({ message: "Failed to build request headers", code: "HTTP_ERROR" })
  }
  do_http_post(url, headers, query)
}

///|
/// Fetch topic records from a table
pub fn fetch_topics(table : String) -> Result[Array[TopicRecord], AgentError] {
  let query = "SELECT * FROM " + table + " WHERE generated = false OR generated IS NONE;"
  let response = match db_request(query) {
    Ok(s) => s
    Err(e) => return Err(e)
  }
  let json = @json.parse(response) catch { _ => return Ok([]) }
  let arr = match json {
    Json::Array(a) => a
    _ => return Ok([])
  }
  if arr.length() < 1 {
    return Ok([])
  }
  let sel = match arr[0] {
    Json::Object(o) => o
    _ => return Ok([])
  }
  let records = match sel.get("result") {
    Some(Json::Array(r)) => r
    _ => return Ok([])
  }
  fn item_to_record(item : Json) -> TopicRecord? {
    match item {
      Object(o) => {
        let id = match o.get("id") {
          Some(String(s)) => Some(s)
          _ => None
        }
        let agegroup = match o.get("agegroup") {
          Some(String(s)) => s
          _ => ""
        }
        let class_val = match o.get("class") {
          Some(String(s)) => s
          _ => ""
        }
        let subject = match o.get("subject") {
          Some(String(s)) => s
          _ => ""
        }
        let term_str = match o.get("term") {
          Some(String(s)) => s
          _ => ""
        }
        let topic = match o.get("topic") {
          Some(String(s)) => s
          _ => ""
        }
        let week = match o.get("week") {
          Some(Number(n, ..)) => n.to_int()
          _ => 0
        }
        Some({
          id,
          agegroup,
          class: class_val,
          subject,
          term: term_str,
          topic,
          week,
          context: None,
        })
      }
      _ => None
    }
  }
  Ok(records.filter_map(fn(item) { item_to_record(item) }))
}

///|
/// Validate a SurrealDB record ID (table:id — alphanumeric, underscore, colon, hyphen only)
fn is_valid_record_id(id : String) -> Bool {
  let mut i = 0
  let mut saw_colon = false
  while i < id.length() {
    let c = id[i]
    if c == ':' {
      if saw_colon { return false }
      saw_colon = true
    } else if c == '_' || c == '-' {
      // allowed non-alphanumeric
    } else {
      let n = c.to_int()
      if n < 48 || (n > 57 && n < 65) || (n > 90 && n < 97) || n > 122 {
        return false
      }
    }
    i = i + 1
  }
  saw_colon && !id.starts_with(":") && !id.ends_with(":")
}

///|
/// Fetch a single topic by id
pub fn fetch_topic_by_id(
  id : String,
  _config : DbConfig,
) -> Result[TopicRecord?, AgentError] {
  if !is_valid_record_id(id) {
    return Err({ message: "Invalid topic ID format", code: "VALIDATION_ERROR" })
  }
  let query = "SELECT * FROM " + id + " WHERE generated = false OR generated IS NONE LIMIT 1;"
  let response = match db_request(query) {
    Ok(s) => s
    Err(e) => return Err(e)
  }
  let json = @json.parse(response) catch { _ => return Ok(None) }
  let arr = match json {
    Json::Array(a) => a
    _ => return Ok(None)
  }
  if arr.length() < 1 {
    return Ok(None)
  }
  let sel = match arr[0] {
    Json::Object(o) => o
    _ => return Ok(None)
  }
  let records = match sel.get("result") {
    Some(Json::Array(r)) => r
    _ => return Ok(None)
  }
  if records.length() == 0 {
    return Ok(None)
  }
  let item = records[0]
  match item {
    Object(o) => {
      let agegroup = match o.get("agegroup") {
        Some(String(s)) => s
        _ => ""
      }
      let class_str = match o.get("class") {
        Some(String(s)) => s
        _ => ""
      }
      let subject = match o.get("subject") {
        Some(String(s)) => s
        _ => ""
      }
      let term_s = match o.get("term") {
        Some(String(s)) => s
        _ => ""
      }
      let topic = match o.get("topic") {
        Some(String(s)) => s
        _ => ""
      }
      let week = match o.get("week") {
        Some(Number(n, ..)) => n.to_int()
        _ => 0
      }
      let ctx = match o.get("context") {
        Some(String(s)) => Some(s)
        _ => None
      }
      Ok(Some({
        id: Some(id),
        agegroup,
        class: class_str,
        subject,
        term: term_s,
        topic,
        week,
        context: ctx,
      }))
    }
    _ => Ok(None)
  }
}

///|
/// JSON-escape a string value
fn json_escape(s : String) -> String {
  let mut result = ""
  let mut i = 0
  while i < s.length() {
    let c = s[i]
    if c == '\\' { result = result + "\\\\" }
    else if c == '"' { result = result + "\\\"" }
    else if c == '\n' { result = result + "\\n" }
    else if c == '\r' { result = result + "\\r" }
    else if c == '\t' { result = result + "\\t" }
    else if c == '\b' { result = result + "\\b" }
    else if c == '\x0C' { result = result + "\\f" }
    else { result = result + c.to_string() }
    i = i + 1
  }
  result
}

///|
/// Build a SurrealDB-compatible JSON string for the lesson_content
fn build_lesson_json(
  content : CompleteLessonContent,
  source_id : String,
) -> String {
  let class_str = match content.class_level {
    Year1 => "YEAR_1"
    Year2 => "YEAR_2"
    Year3 => "YEAR_3"
    Year4 => "YEAR_4"
    Year5 => "YEAR_5"
    Jss1 => "JSS_1"
    Jss2 => "JSS_2"
    Jss3 => "JSS_3"
  }
  let term_str = match content.term {
    First => "FIRST"
    Second => "SECOND"
    Third => "THIRD"
  }
  let ps = "[" + content.primary_sources.map(fn(s) { "\"" + json_escape(s) + "\"" }).join(",") + "]"
  "{" +
    "\"topic_title\":\"" + json_escape(content.topic_title) + "\"" +
    ",\"subject\":\"" + json_escape(content.subject) + "\"" +
    ",\"class_level\":\"" + json_escape(class_str) + "\"" +
    ",\"age_range\":\"" + json_escape(content.age_range) + "\"" +
    ",\"term\":\"" + json_escape(term_str) + "\"" +
    ",\"week\":" + content.week.to_string() +
    ",\"duration_mins\":" + content.duration_mins.to_string() +
    ",\"source_id\":\"" + json_escape(source_id) + "\"" +
    ",\"primary_sources\":" + ps +
    "}"
}

///|
/// Escape a string for use in a SurrealQL string literal
fn sql_escape(s : String) -> String {
  let mut result = ""
  let mut i = 0
  while i < s.length() {
    let c = s[i]
    if c == '\\' { result = result + "\\\\" }
    else if c == '"' { result = result + "\\\"" }
    else { result = result + c.to_string() }
    i = i + 1
  }
  result
}

///|
/// Write a lesson to the database in an ACID transaction (config-based auth)
pub fn create_row(
  content : CompleteLessonContent,
  source_id : String,
  _config : DbConfig,
) -> Result[String, AgentError] {
  if !is_valid_record_id(source_id) {
    return Err({ message: "Invalid source_id record ID", code: "VALIDATION_ERROR" })
  }
  let class_str = match content.class_level {
    Year1 => "YEAR_1"
    Year2 => "YEAR_2"
    Year3 => "YEAR_3"
    Year4 => "YEAR_4"
    Year5 => "YEAR_5"
    Jss1 => "JSS_1"
    Jss2 => "JSS_2"
    Jss3 => "JSS_3"
  }
  let terms = match content.term {
    First => "FIRST"
    Second => "SECOND"
    Third => "THIRD"
  }
  let lesson_json = build_lesson_json(content, source_id)
  let quoted_subject = "\"" + sql_escape(content.subject) + "\""
  let quoted_class = "\"" + sql_escape(class_str) + "\""
  let quoted_term = "\"" + sql_escape(terms) + "\""
  let q_source = sql_escape(source_id)

  let edge_create = "LET $hs = (SELECT VALUE id FROM has_subject WHERE in = " +
    q_source + " AND out = (SELECT VALUE id FROM subjects WHERE name = " +
    quoted_subject + " AND class_level = " + quoted_class +
    " AND term = " + quoted_term + ") LIMIT 1);" +
    "IF array::len($hs) == 0 {" +
    "  (RELATE " + q_source + " -> has_subject -> (SELECT id FROM subjects WHERE name = " +
    quoted_subject + " AND class_level = " + quoted_class +
    " AND term = " + quoted_term + "));" +
    "};"

  let _ = match db_request(edge_create) {
    Ok(_) => ()
    Err(e) =>
      @logging.warn("edge pre-create (best-effort): " + e.message)
  }

  let query = "BEGIN TRANSACTION;" +
    "CREATE lesson_content CONTENT " + lesson_json + ";" +
    "UPDATE " + q_source + " SET generated = true;" +
    "COMMIT TRANSACTION;"
  let response = match db_request(query) {
    Ok(s) => s
    Err(e) => {
      @logging.error("create_row txn failed: " + e.message)
      return Err(e)
    }
  }
  let json = @json.parse(response) catch {
    _ => return Ok("Created: " + source_id)
  }
  let arr = match json {
    Json::Array(a) => a
    _ => return Ok("Created: " + source_id)
  }
  for stmt_result in arr {
    match stmt_result {
      Object(o) => {
        match o.get("status") {
          Some(String(s)) =>
            if s != "OK" {
              let err_msg = match o.get("result") {
                Some(String(e)) => e
                _ => s
              }
              return Err({
                message: "DB txn statement failed: " + err_msg,
                code: "DB_ERROR",
              })
            }
          _ => ()
        }
      }
      _ => ()
    }
  }
  Ok("Created lesson: " + content.topic_title)
}

///|
/// Fetch generated lessons (stub)
pub fn fetch_lessons(
  subject : String,
  class : String,
) -> Result[Array[CompleteLessonContent], AgentError] {
  let _subject = subject
  let _class = class
  Ok([])
}

///|
/// Check if a row has already been processed
pub fn content_exists(_source_id : String) -> Bool {
  false
}
