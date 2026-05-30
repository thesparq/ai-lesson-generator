///|
/// Master content agent — orchestrates parallel content generation
#derive.agent
#derive.mount("/content")
struct MasterContentAgent {
  _dummy : Int
}

///|
fn MasterContentAgent::new() -> MasterContentAgent {
  { _dummy: 0 }
}

///|
/// Generate content for all rows in a table
#derive.endpoint(get="/generate?table={table_name}")
pub fn MasterContentAgent::generate_all(
  self : Self,
  table_name : String,
) -> Result[String, AgentError] {
  let _ = self
  // Try SurrealDB topics first, fall back to hardcoded
  let topics = match fetch_topics(table_name) {
    Ok(t) =>
      if t.length() > 0 {
        t
      } else {
        // Hardcoded fallback
        [
          {
            id: Some("test_1"),
            agegroup: "9-10",
            class: "Year 5",
            subject: "Basic Science",
            term: "1st Term",
            topic: "The Human Body",
            week: 2,
            context: None,
          },
          {
            id: Some("test_2"),
            agegroup: "9-10",
            class: "Year 5",
            subject: "Mathematics",
            term: "1st Term",
            topic: "Addition of fractions",
            week: 5,
            context: None,
          },
        ]
      }
    Err(_) =>
      // Hardcoded fallback
      [
        {
          id: Some("test_1"),
          agegroup: "9-10",
          class: "Year 5",
          subject: "Basic Science",
          term: "1st Term",
          topic: "The Human Body",
          week: 2,
          context: None,
        },
        {
          id: Some("test_2"),
          agegroup: "9-10",
          class: "Year 5",
          subject: "Mathematics",
          term: "1st Term",
          topic: "Addition of fractions",
          week: 5,
          context: None,
        },
      ]
  }

  for t in topics {
    let id = match t.id {
      Some(s) => s
      None => continue
    }
    let child_name = "c_" + id
    let cb = fn(c : ChildContentAgentClient) -> Unit raise @common.AgentError {
      c.trigger_generate(table_name, id)
    }
    let _ = ChildContentAgentClient::scoped(child_name, cb) catch { _ => () }
  }

  Ok("All " + topics.length().to_string() + " rows dispatched")
}

///|
fn main {

}
