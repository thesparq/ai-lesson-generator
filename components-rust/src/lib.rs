mod pdf_engine;

use base64::engine::general_purpose;
use base64::Engine;
use golem_rust::agentic::{Config, Secret};
use golem_rust::{
    ConfigSchema, Schema, agent_definition, agent_implementation, agentic::UnstructuredBinary,
    endpoint,
};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use wstd::http::{Body, Client, HeaderValue, Method, Request};

use pdf_engine::pdf_engine;

// ============================================================
// SurrealDB Config (shared secrets)
// ============================================================

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

// ============================================================
// Data Types
// ============================================================

#[derive(Debug, Clone, Serialize, Deserialize, Schema)]
pub struct AgentError {
    pub message: String,
    pub code: String,
}

#[derive(Schema, Clone)]
pub struct PdfFile {
    pub content_type: String,
    pub data: Vec<u8>,
}

impl From<String> for AgentError {
    fn from(err: String) -> Self {
        AgentError {
            message: err,
            code: "ERROR".to_string(),
        }
    }
}

// ============================================================
// Agent Definition
// ============================================================

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
        Self {
            subject,
            class,
            mode,
            config,
        }
    }

    async fn pdf_generator(&mut self) -> UnstructuredBinary<String> {
        let config = self.config.get();
        let records = match fetch_lessons(&self.subject, &self.class, &config).await {
            Ok(records) => records,
            Err(err) => {
                println!("Error: {}", err.message);
                return UnstructuredBinary::Inline {
                    data: err.message.into_bytes(),
                    mime_type: "text/plain".to_string(),
                };
            }
        };

        if records.is_empty() {
            println!("No lessons found for {} {}", self.subject, self.class);
            return UnstructuredBinary::Inline {
                mime_type: "text/plain".to_string(),
                data: format!(
                    "No lesson content found for {} {}",
                    self.subject, self.class
                )
                .into_bytes(),
            };
        }

        match pdf_engine(records, &self.subject, &self.class, &self.mode) {
            Ok(pdf) => UnstructuredBinary::Inline {
                mime_type: "application/pdf".to_string(),
                data: pdf,
            },
            Err(err) => {
                println!("Error: {}", err.message);
                UnstructuredBinary::Inline {
                    mime_type: "text/plain".to_string(),
                    data: err.message.into_bytes(),
                }
            }
        }
    }
}

// ============================================================
// SurrealDB fetch_lessons (graph traversal on lessons table)
// ============================================================

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(default)]
pub struct CompleteLessonContent {
    pub topic_title: String,
    pub subject: String,
    pub class_level: String,
    pub age_range: String,
    pub term: String,
    pub week: i32,
    pub duration_mins: i32,
    pub introduction: String,
    pub conclusion: String,
    pub key_points: Vec<String>,
    pub prior_knowledge: Vec<String>,
    pub materials: Vec<String>,
    pub formative_assessment: String,
    pub summative_assessment: String,
    pub success_criteria: Vec<String>,
    pub remediation: String,
    pub extension_activities: Vec<String>,
    pub primary_sources: Vec<String>,
    pub textbook_references: Vec<String>,
    pub teacher_tips: String,
    pub content_sections: Vec<ContentSectionJson>,
    pub lesson_steps: Vec<LessonStepJson>,
    pub objectives: Vec<ObjectiveJson>,
    pub mcq_questions: Vec<McqJson>,
    pub theoretical_questions: Vec<TheoryJson>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct McqJson {
    pub question: String,
    pub option_a: String,
    pub option_b: String,
    pub option_c: String,
    #[serde(alias = "correctAnswer")]
    pub correct_answer: String,
    pub explanation: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct TheoryJson {
    pub question: String,
    pub parts: Vec<String>,
    #[serde(alias = "modelAnswer")]
    pub model_answer: String,
    #[serde(alias = "markingScheme")]
    pub marking_scheme: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct ContentSectionJson {
    pub section_number: Option<i32>,
    pub header: String,
    pub body: String,
    pub sub_points: Option<Vec<SubPointJson>>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct SubPointJson {
    pub sub_number: String,
    pub text: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct LessonStepJson {
    pub step_number: i32,
    pub phase: String,
    pub duration_mins: i32,
    pub teacher_actions: String,
    pub pupil_activities: String,
    pub teaching_strategy: String,
    pub assessment: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct ObjectiveJson {
    pub objective: String,
    pub taxonomy_level: String,
}

/// Fetch generated lessons from the `lessons` table using graph traversal
pub async fn fetch_lessons(
    subject: &str,
    class: &str,
    config: &DbConfig,
) -> Result<Vec<CompleteLessonContent>, AgentError> {
    let qclass = class.replace('"', "\\\"");
    let qsubject = subject.replace('"', "\\\"");
    let query = format!(
         "USE NS {} DB {}; \
          SELECT topic_title, \
                 class_subject.out.name AS subject, \
                 class_subject.in.name AS class_level, \
                 class_subject.in.age_range AS age_range, \
                 term.name AS term, \
                 week AS week, \
                 duration_mins AS duration_mins, \
                 introduction, conclusion, teacher_tips, \
                 remediation, formative_assessment, summative_assessment, \
                 objectives, content_sections, key_points, lesson_steps, \
                 mcq_questions, theoretical_questions, \
                 materials, prior_knowledge, success_criteria, \
                 extension_activities, textbook_references, primary_sources \
          FROM lessons \
          WHERE class_subject.in.name = \"{}\" \
            AND class_subject.out.name = \"{}\" \
          ORDER BY term.name ASC, week ASC;",
        config.db_namespace.get(),
        config.db_name.get(),
        qclass,
        qsubject,
    );
    let response = db_request(query, config).await?;

    let records = if let Some(select_result) = response.get(1) {
        if let Some(status) = select_result.get("status") {
            if status != "OK" {
                return Err(AgentError {
                    message: format!("Query failed with status: {:?}", status),
                    code: "QUERY_FAILED".to_string(),
                });
            }
        }
        match select_result.get("result") {
            Some(Value::Array(arr)) => {
                serde_json::from_value(Value::Array(arr.clone())).map_err(|e| AgentError {
                    message: format!("Failed to deserialize records: {:?}", e),
                    code: "DESERIALIZE_ERROR".to_string(),
                })?
            }
            Some(Value::Null) => Vec::new(),
            Some(other) => {
                return Err(AgentError {
                    message: format!("Unexpected result type: {:?}", other),
                    code: "UNEXPECTED_RESULT".to_string(),
                });
            }
            None => {
                return Err(AgentError {
                    message: "No 'result' field in response".to_string(),
                    code: "MISSING_RESULT".to_string(),
                });
            }
        }
    } else {
        return Err(AgentError {
            message: format!("Expected at least 2 results, got {}", response.len()),
            code: "INSUFFICIENT_RESULTS".to_string(),
        });
    };
    println!("✓ Fetched {} records from db", records.len());
    Ok(records)
}

async fn db_request(query: String, config: &DbConfig) -> Result<Vec<Value>, AgentError> {
    let url = config.db_url.get();
    let username = config.db_username.get();
    let password = config.db_password.get();
    let ns = config.db_namespace.get();
    let db_name_val = config.db_name.get();

    let url = if url.ends_with("/sql") {
        url
    } else {
        url + "/sql"
    };

    let creds = format!("{}:{}", username, password);
    let encoded = general_purpose::STANDARD.encode(creds.as_bytes());
    let auth_value = format!("Basic {}", encoded);

    let request = Request::builder()
        .method(Method::POST)
        .uri(url.as_str())
        .header(
            "Accept",
            HeaderValue::from_str("application/json").map_err(|e| e.to_string())?,
        )
        .header(
            "Authorization",
            HeaderValue::from_str(&auth_value).map_err(|e| e.to_string())?,
        )
        .header(
            "NS",
            HeaderValue::from_str(&ns).map_err(|e| e.to_string())?,
        )
        .header(
            "DB",
            HeaderValue::from_str(&db_name_val).map_err(|e| e.to_string())?,
        )
        .body::<Body>(query.into())
        .map_err(|e| AgentError {
            message: e.to_string(),
            code: "REQUEST_BUILD_ERROR".to_string(),
        })?;

    let response = Client::new().send(request).await.map_err(|e| AgentError {
        message: format!("HTTP request failed: {:?}", e),
        code: "CONNECTION_ERROR".to_string(),
    })?;

    let status = response.status();
    if !status.is_success() {
        return Err(AgentError {
            message: format!("Query failed with status: {}", status),
            code: "QUERY_ERROR".to_string(),
        });
    }

    let mut body = response.into_body();
    let response_json: Vec<Value> = body.json().await.map_err(|e| AgentError {
        message: format!("Failed to parse JSON: {:?}", e),
        code: "PARSE_ERROR".to_string(),
    })?;
    Ok(response_json)
}
