///|
/// Helper: sleep for a given number of milliseconds
fn sleep_ms(ms : UInt64) -> Unit {
  let nanos = ms * 1000000UL
  let pollable = @monotonicClock.subscribe_duration(nanos)
  pollable.block()
}

///|
/// Helper: convert a string to Bytes for promise payloads
fn string_to_bytes(s : String) -> Bytes {
  @utf8.encode(s)
}

///|
/// Child content agent — processes one topic, completes a promise with the result
#derive.agent
struct ChildContentAgent {
  id : String
  config : @config.Config[DbConfig]
}

///|
fn ChildContentAgent::new(
  id : String,
  config : @config.Config[DbConfig],
) -> ChildContentAgent {
  { id, config }
}

///|
/// Generate content for this child's topic and complete the promise
pub fn ChildContentAgent::generate(
  self : Self,
  topic_id : String,
  promise_key : PromiseKey,
) -> Unit {
  let promise_id = to_promise_id(promise_key)
  sleep_ms(500)
  let config = self.config.value

  let topic = match fetch_topic_by_id(topic_id, config) {
    Ok(Some(t)) => t
    Ok(None) => {
      let _ = @api.complete_promise(
        promise_id,
        string_to_bytes("skipped: not found or already generated"),
      )
      return
    }
    Err(e) => {
      let _ = @api.complete_promise(
        promise_id,
        string_to_bytes("db error: " + e.message),
      )
      return
    }
  }

  let request = convert_topic_to_request(topic)
  @logging.info("calling BAML for: " + topic.topic)
  let content = match call_baml_generate_lesson(request) {
    Ok(c) => c
    Err(e) => {
      @logging.error("BAML failed: " + e.message)
      let _ = @api.complete_promise(
        promise_id,
        string_to_bytes("BAML error: " + e.message),
      )
      return
    }
  }
  @logging.info("BAML OK: " + content.topic_title)

  @logging.info("writing to DB: " + content.topic_title)
  let result = create_row(content, topic_id, config)
  match result {
    Ok(msg) => {
      let _ = @api.complete_promise(promise_id, string_to_bytes(msg))
      @logging.info("DB OK: " + msg)
    }
    Err(e) => {
      let _ = @api.complete_promise(
        promise_id,
        string_to_bytes("DB error: " + e.message),
      )
      @logging.error("DB error: " + e.message)
    }
  }
}
