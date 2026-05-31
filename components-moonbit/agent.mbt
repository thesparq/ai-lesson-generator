///|
/// Master content agent — orchestrates parallel content generation
#derive.agent
struct MasterContentAgent {
  config : @config.Config[DbConfig]
}

///|
fn MasterContentAgent::new(
  config : @config.Config[DbConfig],
) -> MasterContentAgent {
  { config }
}

///|
/// Generate content for all unprocessed topics in a table
pub fn MasterContentAgent::generate_all(
  self : Self,
  table_name : String,
) -> Result[String, AgentError] {
  let topics = match fetch_topics(table_name) {
    Ok(t) => t
    Err(e) => return Err(e)
  }
  if topics.length() == 0 {
    return Ok("No unprocessed topics found")
  }

  let promise_ids : Array[@rpcTypes.PromiseId] = []
  let topic_ids : Array[String] = []

  for i in 0..<topics.length() {
    let t = topics[i]
    let id = match t.id {
      Some(s) => s
      None => continue
    }
    let child_name = "child_" + i.to_string()
    let promise_id = @api.create_promise()
    let promise_key = from_promise_id(promise_id)

    let mut spawned = false
    ChildContentAgentClient::scoped(child_name, fn(child) {
      child.trigger_generate(id, promise_key)
      spawned = true
    }) catch { _ => () }
    if spawned {
      promise_ids.append([promise_id])
      topic_ids.append([id])
    } else {
      @logging.info("child " + id + ": spawn failed")
    }
  }

  let mut processed = 0
  let mut failed = 0

  for i in 0..<promise_ids.length() {
    let result_bytes = @api.await_promise(promise_ids[i])
    let result = @utf8.decode_lossy(result_bytes.view())
    if result.has_prefix("Created lesson") {
      processed = processed + 1
    } else {
      failed = failed + 1
    }
    @logging.info("child " + topic_ids[i] + ": " + result)
  }

  Ok(processed.to_string() + "/" + topics.length().to_string() + " topics processed" +
    (if failed > 0 { " (" + failed.to_string() + " failed)" } else { "" }))
}

///|
fn main {

}
