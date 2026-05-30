///|
/// Get BAML_BASE_URL from environment
fn get_baml_base_url() -> String {
  let envs = @cliEnv.get_environment()
  for env in envs {
    let (key, value) = env
    if key == "BAML_BASE_URL" {
      return value
    }
  }
  "http://localhost:8001"
}

///|
/// Convert class string to BAML ClassLevel enum
fn class_to_baml_level(class : String) -> ClassLevel {
  match class {
    "Year 1" => ClassLevel::Primary1
    "Year 2" => ClassLevel::Primary2
    "Year 3" => ClassLevel::Primary3
    "Year 4" => ClassLevel::Primary4
    "Year 5" => ClassLevel::Primary5
    "Jss 1" => ClassLevel::Jss1
    "Jss 2" => ClassLevel::Jss2
    "Jss 3" => ClassLevel::Jss3
    _ => ClassLevel::Primary1
  }
}

///|
/// Convert term string to BAML Term enum
fn term_to_baml_term(term : String) -> Term {
  match term {
    "1st Term" | "Noel Term" => Term::First
    "2nd Term" | "Calvary Term" => Term::Second
    "3rd Term" | "Summer Term" => Term::Third
    _ => Term::First
  }
}

///|
/// Convert a TopicRecord to a GenerateNigerianLessonRequest
pub fn convert_topic_to_request(
  topic : TopicRecord,
) -> GenerateNigerianLessonRequest {
  {
    age_group: topic.agegroup,
    class_level: class_to_baml_level(topic.class),
    subject: topic.subject,
    term: term_to_baml_term(topic.term),
    topic: topic.topic,
    week: topic.week,
    context: topic.context,
  }
}

///|
/// Serialize a GenerateNigerianLessonRequest to a JSON string
fn request_to_json(request : GenerateNigerianLessonRequest) -> String {
  let class_str = match request.class_level {
    Primary1 => "PRIMARY_1"
    Primary2 => "PRIMARY_2"
    Primary3 => "PRIMARY_3"
    Primary4 => "PRIMARY_4"
    Primary5 => "PRIMARY_5"
    Jss1 => "JSS_1"
    Jss2 => "JSS_2"
    Jss3 => "JSS_3"
  }
  let term_str = match request.term {
    First => "FIRST"
    Second => "SECOND"
    Third => "THIRD"
  }
  let context_str = match request.context {
    Some(c) => "\"" + c + "\""
    None => "null"
  }
  "{" +
  "\"age_group\": \"" +
  request.age_group +
  "\", " +
  "\"class_level\": \"" +
  class_str +
  "\", " +
  "\"subject\": \"" +
  request.subject +
  "\", " +
  "\"term\": \"" +
  term_str +
  "\", " +
  "\"topic\": \"" +
  request.topic +
  "\", " +
  "\"week\": " +
  request.week.to_string() +
  ", " +
  "\"context\": " +
  context_str +
  "}"
}

///|
/// Parse a URL into (scheme, authority, path)
fn parse_url(url : String) -> (@wasiTypes.Scheme, String, String) {
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
        None => (scheme, rest, "")
      }
    }
    None => (@wasiTypes.Http, url, "")
  }
}

///|
/// Call the BAML GenerateNigerianLesson endpoint
pub fn call_baml_generate_lesson(
  request : GenerateNigerianLessonRequest,
) -> Result[CompleteLessonContent, AgentError] {
  let base_url = get_baml_base_url()
  let (scheme, authority, path) = parse_url(base_url)
  let body_json = request_to_json(request)

  let headers = @wasiTypes.Fields::from_list([
    ("Content-Type", str_to_bytes("application/json")),
    ("Accept", str_to_bytes("application/json")),
  ]).unwrap()

  let req = @wasiTypes.OutgoingRequest::outgoing_request(headers)
  let _ = req.set_method(@wasiTypes.Post)
  let _ = req.set_scheme(Some(scheme))
  let _ = req.set_authority(Some(authority))
  let _ = req.set_path_with_query(Some(path + "/call/GenerateNigerianLesson"))

  let out_body = req.body().unwrap()
  let output_stream = out_body.write().unwrap()
  output_stream.blocking_write_and_flush(str_to_bytes(body_json)).unwrap()
  output_stream.drop()
  @wasiTypes.OutgoingBody::finish(out_body, None).unwrap()

  let future_response = @http.handle(req, None).unwrap()
  let pollable = future_response.subscribe()
  pollable.block()
  let response = future_response.get().unwrap().unwrap().unwrap()
  let _status = response.status()
  let incoming_body = response.consume().unwrap()
  let stream = incoming_body.stream().unwrap()
  let bytes = stream.blocking_read(1048576UL).unwrap()
  stream.drop()
  let _ = @wasiTypes.IncomingBody::finish(incoming_body)

  let body_str = bytes_to_str(bytes)
  parse_lesson_content_json(body_str)
}

///|
/// Extract a string field from a JSON object
fn obj_get_str(obj : Map[String, Json], key : String) -> String {
  match obj.get(key) {
    Some(v) =>
      match v.as_string() {
        Some(s) => s
        None => ""
      }
    None => ""
  }
}

///|
/// Extract an int field from a JSON object
fn obj_get_int(obj : Map[String, Json], key : String) -> Int {
  match obj.get(key) {
    Some(v) =>
      match v.as_number() {
        Some(n) => n.to_int()
        None => 0
      }
    None => 0
  }
}

///|
/// Helper: parse Json array items as objects with callback
fn[T] map_json_array(val : Json?, f : (Map[String, Json]) -> T?) -> Array[T] {
  match val {
    Some(v) =>
      match v.as_array() {
        Some(arr) =>
          arr.filter_map(fn(item) {
            match item.as_object() {
              Some(o) => f(o)
              None => None
            }
          })
        None => []
      }
    None => []
  }
}

///|
/// Parse a JSON string array
fn parse_str_arr(val : Json?) -> Array[String] {
  match val {
    Some(v) =>
      match v.as_array() {
        Some(arr) => arr.filter_map(fn(item) { item.as_string() })
        None => []
      }
    None => []
  }
}

///|
/// Parse objectives
fn parse_objectives(val : Json?) -> Array[LessonObjective] {
  map_json_array(val, fn(o) {
    Some({
      objective: obj_get_str(o, "objective"),
      taxonomy_level: obj_get_str(o, "taxonomy_level"),
    })
  })
}

///|
/// Parse content sections
fn parse_content_sections(val : Json?) -> Array[ContentSection] {
  map_json_array(val, fn(o) {
    Some({
      section_number: match o.get("section_number") {
        Some(n) =>
          match n.as_number() {
            Some(num) => Some(num.to_int())
            None => None
          }
        None => None
      },
      header: obj_get_str(o, "header"),
      body: obj_get_str(o, "body"),
      sub_points: parse_sub_points(o.get("sub_points")),
    })
  })
}

///|
/// Parse sub points
fn parse_sub_points(val : Json?) -> Array[ContentSubPoint]? {
  match val {
    Some(v) =>
      match v.as_array() {
        Some(arr) =>
          Some(
            arr.filter_map(fn(item) {
              match item.as_object() {
                Some(o) =>
                  Some({
                    sub_number: obj_get_str(o, "sub_number"),
                    text: obj_get_str(o, "text"),
                  })
                None => None
              }
            }),
          )
        None => None
      }
    None => None
  }
}

///|
/// Parse lesson steps
fn parse_lesson_steps(val : Json?) -> Array[LessonStep] {
  map_json_array(val, fn(o) {
    Some({
      step_number: obj_get_int(o, "step_number"),
      phase: obj_get_str(o, "phase"),
      duration_mins: obj_get_int(o, "duration_mins"),
      teacher_actions: obj_get_str(o, "teacher_actions"),
      pupil_activities: obj_get_str(o, "pupil_activities"),
      teaching_strategy: obj_get_str(o, "teaching_strategy"),
      assessment: match o.get("assessment") {
        Some(a) =>
          match a.as_string() {
            Some(s) => Some(s)
            None => None
          }
        None => None
      },
    })
  })
}

///|
/// Parse MCQs
fn parse_mcqs(val : Json?) -> Array[McqQuestion] {
  map_json_array(val, fn(o) {
    Some({
      question: obj_get_str(o, "question"),
      option_a: obj_get_str(o, "option_a"),
      option_b: obj_get_str(o, "option_b"),
      option_c: obj_get_str(o, "option_c"),
      correct_answer: obj_get_str(o, "correct_answer"),
      explanation: obj_get_str(o, "explanation"),
    })
  })
}

///|
/// Parse theory questions
fn parse_theory(val : Json?) -> Array[TheoreticalQuestion] {
  map_json_array(val, fn(o) {
    Some({
      question: obj_get_str(o, "question"),
      parts: parse_str_arr(o.get("parts")),
      model_answer: obj_get_str(o, "model_answer"),
      marking_scheme: obj_get_str(o, "marking_scheme"),
    })
  })
}

///|
/// Parse a JSON string into CompleteLessonContent using @json
fn parse_lesson_content_json(
  json_str : String,
) -> Result[CompleteLessonContent, AgentError] {
  let sv : StringView = json_str
  let parsed = @json.parse(sv) catch {
    _ =>
      // Fallback: try string-based extraction for large responses
      return fallback_parse(json_str)
  }
  let obj = match parsed {
    Object(m) => m
    _ => return fallback_parse(json_str)
  }
  let class_level_val = match obj.get("class_level") {
    Some(String(s)) =>
      match s {
        "PRIMARY_1" => ClassLevel::Primary1
        "PRIMARY_2" => ClassLevel::Primary2
        "PRIMARY_3" => ClassLevel::Primary3
        "PRIMARY_4" => ClassLevel::Primary4
        "PRIMARY_5" => ClassLevel::Primary5
        "JSS_1" => ClassLevel::Jss1
        "JSS_2" => ClassLevel::Jss2
        "JSS_3" => ClassLevel::Jss3
        _ => ClassLevel::Primary1
      }
    _ => ClassLevel::Primary1
  }
  let term_val = match obj.get("term") {
    Some(String(s)) =>
      match s {
        "FIRST" => Term::First
        "SECOND" => Term::Second
        "THIRD" => Term::Third
        _ => Term::First
      }
    _ => Term::First
  }
  fn obj_str(o : Map[String, Json], k : String) -> String {
    match o.get(k) {
      Some(String(s)) => s
      _ => ""
    }
  }
  fn obj_int(o : Map[String, Json], k : String) -> Int {
    match o.get(k) {
      Some(Number(n, ..)) => n.to_int()
      _ => 0
    }
  }
  fn str_arr(o : Map[String, Json], k : String) -> Array[String] {
    match o.get(k) {
      Some(Array(items)) => {
        let r : Array[String] = []
        for item in items {
          match item {
            String(s) => r.append([s])
            _ => ()
          }
        }
        r
      }
      _ => []
    }
  }
  fn empty_arr(_o : Map[String, Json], _k : String) -> Array[String] {
    []
  }
  fn empty_sections(
    _o : Map[String, Json],
    _k : String,
  ) -> Array[ContentSection] {
    []
  }
  fn empty_steps(_o : Map[String, Json], _k : String) -> Array[LessonStep] {
    []
  }
  fn empty_objectives(
    _o : Map[String, Json],
    _k : String,
  ) -> Array[LessonObjective] {
    []
  }
  fn empty_mcqs(_o : Map[String, Json], _k : String) -> Array[McqQuestion] {
    []
  }
  fn empty_theory(
    _o : Map[String, Json],
    _k : String,
  ) -> Array[TheoreticalQuestion] {
    []
  }

  Ok({
    topic_title: obj_str(obj, "topic_title"),
    subject: obj_str(obj, "subject"),
    class_level: class_level_val,
    age_range: obj_str(obj, "age_range"),
    term: term_val,
    week: obj_int(obj, "week"),
    duration_mins: obj_int(obj, "duration_mins"),
    introduction: obj_str(obj, "introduction"),
    conclusion: obj_str(obj, "conclusion"),
    teacher_tips: obj_str(obj, "teacher_tips"),
    remediation: obj_str(obj, "remediation"),
    formative_assessment: obj_str(obj, "formative_assessment"),
    summative_assessment: obj_str(obj, "summative_assessment"),
    objectives: empty_objectives(obj, "objectives"),
    content_sections: empty_sections(obj, "content_sections"),
    lesson_steps: empty_steps(obj, "lesson_steps"),
    key_points: str_arr(obj, "key_points"),
    mcq_questions: empty_mcqs(obj, "mcq_questions"),
    theoretical_questions: empty_theory(obj, "theoretical_questions"),
    prior_knowledge: str_arr(obj, "prior_knowledge"),
    materials: str_arr(obj, "materials"),
    success_criteria: str_arr(obj, "success_criteria"),
    extension_activities: str_arr(obj, "extension_activities"),
    primary_sources: str_arr(obj, "primary_sources"),
    textbook_references: str_arr(obj, "textbook_references"),
  })
}

///|
/// Fallback: extract fields from BAML JSON (handles "key": "value" with space)
fn fallback_parse(
  json_str : String,
) -> Result[CompleteLessonContent, AgentError] {
  fn val(s : String, k : String) -> String {
    let pat = "\"" + k + "\": \""
    match s.split_once(pat) {
      Some((_, a)) =>
        match a.split_once("\"") {
          Some((v, _)) => v.to_string()
          None => ""
        }
      None => {
        // Try without space: "key":"value"
        let pat2 = "\"" + k + "\":\""
        match s.split_once(pat2) {
          Some((_, a)) =>
            match a.split_once("\"") {
              Some((v, _)) => v.to_string()
              None => ""
            }
          None => ""
        }
      }
    }
  }
  let c = val(json_str, "class_level")
  let class_level = match c {
    "PRIMARY_1" => ClassLevel::Primary1
    "PRIMARY_2" => ClassLevel::Primary2
    "PRIMARY_3" => ClassLevel::Primary3
    "PRIMARY_4" => ClassLevel::Primary4
    "PRIMARY_5" => ClassLevel::Primary5
    "JSS_1" => ClassLevel::Jss1
    "JSS_2" => ClassLevel::Jss2
    "JSS_3" => ClassLevel::Jss3
    _ => ClassLevel::Primary1
  }
  let t = val(json_str, "term")
  let term = match t {
    "FIRST" => Term::First
    "SECOND" => Term::Second
    "THIRD" => Term::Third
    _ => Term::First
  }
  Ok({
    topic_title: val(json_str, "topic_title"),
    subject: val(json_str, "subject"),
    class_level,
    age_range: val(json_str, "age_range"),
    term,
    week: 0,
    duration_mins: 0,
    introduction: "",
    conclusion: "",
    teacher_tips: "",
    remediation: "",
    formative_assessment: "",
    summative_assessment: "",
    objectives: [],
    content_sections: [],
    lesson_steps: [],
    key_points: [],
    mcq_questions: [],
    theoretical_questions: [],
    prior_knowledge: [],
    materials: [],
    success_criteria: [],
    extension_activities: [],
    primary_sources: [],
    textbook_references: [],
  })
}
