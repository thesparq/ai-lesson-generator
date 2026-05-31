///|
/// SurrealDB connection configuration (all fields are secrets)
#derive.config
pub(all) struct DbConfig {
  host : @config.Secret[String]
  username : @config.Secret[String]
  password : @config.Secret[String]
  ns : @config.Secret[String]
  database : @config.Secret[String]
}
