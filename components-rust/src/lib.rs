mod pdf_engine;

use golem_rust::{
    Schema, agent_definition, agent_implementation, agentic::UnstructuredBinary, endpoint,
};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use wstd::http::{Body, Client, HeaderValue, Method, Request};

use pdf_engine::pdf_engine;

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
    fn new(subject: String, class: String, mode: String) -> Self;
    #[endpoint(get = "/")]
    // async fn pdf_generator(&mut self) -> PdfFile;
    async fn pdf_generator(&mut self) -> UnstructuredBinary<String>;
}

pub struct PdfImpl {
    subject: String,
    class: String,
    mode: String,
}

#[agent_implementation]
impl PdfAgent for PdfImpl {
    fn new(subject: String, class: String, mode: String) -> Self {
        Self {
            subject,
            class,
            mode,
        }
    }

    async fn pdf_generator(&mut self) -> UnstructuredBinary<String> {
        let records = match fetch_lessons(&self.subject, &self.class).await {
            Ok(records) => records,
            Err(err) => {
                println!("Error: {}", err.message);
                // return PdfFile {
                //     content_type: "text/plain".to_string(),
                //     data: err.message.into_bytes(),
                // };
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
// SurrealDB fetch_lessons (inlined, no BAML dependency)
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

pub async fn fetch_lessons(
    subject: &str,
    class: &str,
) -> Result<Vec<CompleteLessonContent>, AgentError> {
    let query = format!(
        "USE NS main DB `johnethel-school-generated-lessons`; \
         SELECT * FROM lesson_content \
         WHERE \"{}\" in class_level AND \"{}\" in subject \
         ORDER BY term ASC, week ASC;",
        class, subject
    );
    let response = db_request(query).await?;

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

async fn db_request(query: String) -> Result<Vec<Value>, AgentError> {
    let url =
        std::env::var("SURREAL_DB_URL").unwrap_or_else(|_| "http://localhost:8000/sql".to_string());
    let url = if url.ends_with("/sql") {
        url
    } else {
        url + "/sql"
    };

    let request = Request::builder()
        .method(Method::POST)
        .uri(url.as_str())
        .header(
            "Accept",
            HeaderValue::from_str("application/json").map_err(|e| e.to_string())?,
        )
        .header(
            "Authorization",
            HeaderValue::from_str(
                "Basic Z29sZW06ejVFZFpoRmFIWmNpMjl4d2F6NFp1VUVtbWlkZ0g5S0FLem0wa0hSYUpBPQ==",
            )
            .map_err(|e| e.to_string())?,
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
