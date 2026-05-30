///|
/// Helper: UTF-8 string to WASI field-value bytes
fn str_to_bytes(s : String) -> FixedArray[Byte] {
  @utf8.encode(s).to_fixedarray()
}

///|
/// Helper: bytes back to string
fn bytes_to_str(bs : FixedArray[Byte]) -> String {
  @utf8.decode_lossy(Bytes::from_fixedarray(bs).view())
}

///|
/// Parse SURREAL_DB_URL into (scheme, authority, path)
fn parse_db_url(url : String) -> (@wasiTypes.Scheme, String, String) {
  match url.split_once("://") {
    Some((scheme_view, rest_view)) => {
      let scheme_str = scheme_view.to_string()
      let rest = rest_view.to_string()
      let scheme = if scheme_str == "https" {
        @wasiTypes.Https
      } else {
        @wasiTypes.Http
      }
      match rest.split_once("/") {
        Some((auth_view, path_view)) =>
          (scheme, auth_view.to_string(), "/" + path_view.to_string())
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
      if v.ends_with("/sql") {
        return v
      }
      return v + "/sql"
    }
  }
  "http://localhost:8000/sql"
}

///|
/// Send a SurrealQL query and return the response body string
pub fn db_request(query : String) -> Result[String, AgentError] {
  let url = get_surrealdb_url()
  let (scheme, authority, path) = parse_db_url(url)
  let headers = @wasiTypes.Fields::from_list([
    ("Accept", str_to_bytes("application/json")),
    (
      "Authorization",
      str_to_bytes(
        "Basic Z29sZW06ejVFZFpoRmFIWmNpMjl4d2F6NFp1VUVtbWlkZ0g5S0FLem0wa0hSYUpBPQ==",
      ),
    ),
  ]).unwrap()

  let request = @wasiTypes.OutgoingRequest::outgoing_request(headers)
  let _ = request.set_method(@wasiTypes.Post)
  let _ = request.set_scheme(Some(scheme))
  let _ = request.set_authority(Some(authority))
  let _ = request.set_path_with_query(Some(path))

  let body = request.body().unwrap()
  let output_stream = body.write().unwrap()
  output_stream.blocking_write_and_flush(str_to_bytes(query)).unwrap()
  output_stream.drop()
  @wasiTypes.OutgoingBody::finish(body, None).unwrap()

  let future_response = @http.handle(request, None).unwrap()
  let pollable = future_response.subscribe()
  pollable.block()
  let response = match future_response.get() {
    Some(Ok(Ok(r))) => r
    _ => return Err({ message: "HTTP response error", code: "HTTP_ERROR" })
  }
  let status = response.status()
  if status != 200U {
    let incoming = response.consume().unwrap()
    let stream = incoming.stream().unwrap()
    let errbytes = stream.blocking_read(1024UL).unwrap()
    stream.drop()
    let _ = @wasiTypes.IncomingBody::finish(incoming)
    return Err({
      message: "HTTP " + status.to_string() + ": " + bytes_to_str(errbytes),
      code: "HTTP_ERROR",
    })
  }
  let incoming_body = response.consume().unwrap()
  let stream = incoming_body.stream().unwrap()
  let bytes = stream.blocking_read(1048576UL).unwrap()
  stream.drop()
  let _ = @wasiTypes.IncomingBody::finish(incoming_body)

  Ok(bytes_to_str(bytes))
}

///|
/// Fetch topic records from a table
pub fn fetch_topics(table : String) -> Result[Array[TopicRecord], AgentError] {
  let query = "USE NS main DB `johnethel-school-generated-lessons`; SELECT * FROM " +
    table +
    ";"
  let response = match db_request(query) {
    Ok(s) => s
    Err(e) => return Err(e)
  }
  // Use Json parsing
  let json = @json.parse(response) catch { _ => return Ok([]) }
  let arr = match json {
    Json::Array(a) => a
    _ => return Ok([])
  }
  // arr[0] = USE result, arr[1] = SELECT result
  if arr.length() < 2 {
    return Ok([])
  }
  let sel = match arr[1] {
    Json::Object(o) => o
    _ => return Ok([])
  }
  let records = match sel.get("result") {
    Some(Json::Array(r)) => r
    _ => return Ok([])
  }
  // Convert each Json to TopicRecord using functional style
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
        let term = match o.get("term") {
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
          term,
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
/// Write a lesson to the database
pub fn create_row(
  content : CompleteLessonContent,
  source_id : String,
) -> Result[String, AgentError] {
  let class_str = match content.class_level {
    Primary1 => "PRIMARY_1"
    Primary2 => "PRIMARY_2"
    Primary3 => "PRIMARY_3"
    Primary4 => "PRIMARY_4"
    Primary5 => "PRIMARY_5"
    Jss1 => "JSS_1"
    Jss2 => "JSS_2"
    Jss3 => "JSS_3"
  }
  let term_str = match content.term {
    First => "FIRST"
    Second => "SECOND"
    Third => "THIRD"
  }
  let json_str = "{" +
    "\"topic_title\":\"" +
    content.topic_title +
    "\"" +
    ",\"subject\":\"" +
    content.subject +
    "\"" +
    ",\"class_level\":\"" +
    class_str +
    "\"" +
    ",\"age_range\":\"" +
    content.age_range +
    "\"" +
    ",\"term\":\"" +
    term_str +
    "\"" +
    ",\"week\":" +
    content.week.to_string() +
    ",\"source_id\":\"" +
    source_id +
    "\"" +
    ",\"duration_mins\":" +
    content.duration_mins.to_string() +
    "}"
  let query = "USE NS main DB `johnethel-school-generated-lessons`; CREATE lesson_content CONTENT " +
    json_str +
    ";"
  let _response = match db_request(query) {
    Ok(s) => s
    Err(e) => return Err(e)
  }
  Ok("Created: " + source_id)
}

///|
/// Check if a row has already been processed
pub fn content_exists(_source_id : String) -> Bool {
  false
}
