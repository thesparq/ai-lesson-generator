///|
/// Serialized promise identifier — wraps @rpcTypes.PromiseId data in @schema-compatible fields
#derive.golem_schema
pub(all) struct PromiseKey {
  component_id_high : UInt64
  component_id_low : UInt64
  agent_id : String
  oplog_idx : UInt64
}

///|
/// Convert PromiseKey to @rpcTypes.PromiseId
pub fn to_promise_id(key : PromiseKey) -> @rpcTypes.PromiseId {
  {
    agent_id: {
      component_id: {
        uuid: {
          high_bits: key.component_id_high,
          low_bits: key.component_id_low,
        },
      },
      agent_id: key.agent_id,
    },
    oplog_idx: key.oplog_idx,
  }
}

///|
/// Convert @rpcTypes.PromiseId to PromiseKey
pub fn from_promise_id(pid : @rpcTypes.PromiseId) -> PromiseKey {
  {
    component_id_high: pid.agent_id.component_id.uuid.high_bits,
    component_id_low: pid.agent_id.component_id.uuid.low_bits,
    agent_id: pid.agent_id.agent_id,
    oplog_idx: pid.oplog_idx,
  }
}
