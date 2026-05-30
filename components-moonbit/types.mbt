///|
/// Nigerian school class levels
#derive.golem_schema
pub(all) enum ClassLevel {
  Primary1
  Primary2
  Primary3
  Primary4
  Primary5
  Jss1
  Jss2
  Jss3
}

///|
/// Academic terms
#derive.golem_schema
pub(all) enum Term {
  First
  Second
  Third
}

///|
/// A topic record from the database
#derive.golem_schema
pub(all) struct TopicRecord {
  id : String?
  agegroup : String
  class : String
  subject : String
  term : String
  topic : String
  week : Int
  context : String?
}

///|
/// A lesson objective
#derive.golem_schema
pub(all) struct LessonObjective {
  objective : String
  taxonomy_level : String
}

///|
/// Content sub-point
#derive.golem_schema
pub(all) struct ContentSubPoint {
  sub_number : String
  text : String
}

///|
/// A structured content section
#derive.golem_schema
pub(all) struct ContentSection {
  section_number : Int?
  header : String
  body : String
  sub_points : Array[ContentSubPoint]?
}

///|
/// A lesson step in the lesson plan
#derive.golem_schema
pub(all) struct LessonStep {
  step_number : Int
  phase : String
  duration_mins : Int
  teacher_actions : String
  pupil_activities : String
  teaching_strategy : String
  assessment : String?
}

///|
/// Multiple choice question
#derive.golem_schema
pub(all) struct McqQuestion {
  question : String
  option_a : String
  option_b : String
  option_c : String
  correct_answer : String
  explanation : String
}

///|
/// Theoretical question
#derive.golem_schema
pub(all) struct TheoreticalQuestion {
  question : String
  parts : Array[String]
  model_answer : String
  marking_scheme : String
}

///|
/// Complete generated lesson content — matches BAML's CompleteLessonContent
#derive.golem_schema
pub(all) struct CompleteLessonContent {
  topic_title : String
  subject : String
  class_level : ClassLevel
  age_range : String
  term : Term
  week : Int
  duration_mins : Int
  objectives : Array[LessonObjective]
  introduction : String
  content_sections : Array[ContentSection]
  conclusion : String
  key_points : Array[String]
  mcq_questions : Array[McqQuestion]
  theoretical_questions : Array[TheoreticalQuestion]
  prior_knowledge : Array[String]
  materials : Array[String]
  lesson_steps : Array[LessonStep]
  formative_assessment : String
  summative_assessment : String
  success_criteria : Array[String]
  remediation : String
  extension_activities : Array[String]
  primary_sources : Array[String]
  textbook_references : Array[String]
  teacher_tips : String
}

///|
/// Request payload for the BAML GenerateNigerianLesson endpoint
#derive.golem_schema
pub(all) struct GenerateNigerianLessonRequest {
  age_group : String
  class_level : ClassLevel
  subject : String
  term : Term
  topic : String
  week : Int
  context : String?
}

///|
/// PDF file response
#derive.golem_schema
pub(all) struct PdfFile {
  content_type : String
  data : Bytes
}

///|
/// Agent error
#derive.golem_schema
pub(all) struct AgentError {
  message : String
  code : String
}
