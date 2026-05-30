///|
/// Helper: sleep for a given number of milliseconds
fn sleep_ms(ms : UInt64) -> Unit {
  let nanos = ms * 1000000UL
  let pollable = @monotonicClock.subscribe_duration(nanos)
  pollable.block()
}

///|
/// Find a topic by id in an array
fn find_topic(topics : Array[TopicRecord], row_id : String) -> TopicRecord? {
  for t in topics {
    if t.id == Some(row_id) {
      return Some(t)
    }
  }
  None
}

///|
/// Child content agent — processes one topic row
#derive.agent
struct ChildContentAgent {
  id : String
}

///|
fn ChildContentAgent::new(id : String) -> ChildContentAgent {
  { id, }
}

///|
/// Generate content for a single topic row
pub fn ChildContentAgent::generate(
  self : Self,
  table : String,
  row_id : String,
) -> Unit {
  // 1. Rate-limit delay
  sleep_ms(4000)

  // 2. Fetch topics from SurrealDB
  let topics = match fetch_topics(table) {
    Ok(t) => t
    Err(_) => return
  }
  let topic = find_topic(topics, row_id)
  let topic = match topic {
    Some(t) => t
    None => return
  }

  // 3. Call BAML
  let request = convert_topic_to_request(topic)
  @logging.info("calling BAML for: " + topic.topic)
  let content = match call_baml_generate_lesson(request) {
    Ok(c) => c
    Err(e) => {
      @logging.error("BAML failed: " + e.message)
      return
    }
  }
  @logging.info("BAML OK: " + content.topic_title)

  // 4. Write to DB
  @logging.info("writing to DB: " + content.topic_title)
  let result = create_row(content, row_id)
  match result {
    Ok(msg) => @logging.info("DB OK: " + msg)
    Err(e) => @logging.error("DB error: " + e.message)
  }
}
