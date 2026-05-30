// Nigerian School Workbook Lesson Generator - Optimized BAML Implementation

// ============================================================================
// DATA MODELS
// ============================================================================

enum ClassLevel {
  PRIMARY_1
  PRIMARY_2
  PRIMARY_3
  PRIMARY_4
  PRIMARY_5
  JSS_1
  JSS_2
  JSS_3
}

enum Term {
  FIRST
  SECOND
  THIRD
}

// Structured content sections for easy PDF rendering
class ContentSection {
  section_number int @description("Main section number: 1, 2, 3, etc.")
  header string @description("Section title in UPPERCASE e.g., 'THE HEAD', 'THE TRUNK'")
  body string @description("Main explanatory paragraph for this section")
  sub_points ContentSubPoint[]? @description("Detailed points under this section")
}

class ContentSubPoint {
  sub_number string @description("Sub-point identifier: (i), (ii), (iii) OR (a), (b), (c)")
  text string | ContentSection @description("Complete explanation for this sub-point")
}

class LessonObjective {
  objective string @description("Specific, measurable learning outcome")
  taxonomy_level string @description("Bloom's taxonomy: Knowledge/Comprehension/Application/Analysis")
}

class MultipleChoiceQuestion {
  question string @description("Clear question stem")
  option_a string
  option_b string
  option_c string
  correct_answer string @description("A, B, or C")
  explanation string @description("Why this answer is correct (for teachers only)")
}

class TheoreticalQuestion {
  question string @description("Open-ended or multi-part question")
  parts string[] @description("Sub-questions if applicable (a, b, c)")
  model_answer string @description("Comprehensive 5-mark answer with breakdown (for teachers only)")
  marking_scheme string @description("Point allocation e.g., 2 marks for definition, 3 for examples (for teachers only)")
}

class LessonStep {
  step_number int
  phase string @description("INTRODUCTION/DEVELOPMENT/GENERALIZATION/APPLICATION/CONCLUSION")
  duration_mins int
  teacher_actions string @description("What teacher does/says")
  pupil_activities string @description("Expected pupil responses/actions")
  teaching_strategy string @description("Method used (e.g., questioning, demonstration, group work)")
  assessment string @description("Formative checks during this step") | null
}

class CompleteLessonContent {
  // Metadata
  topic_title string
  subject string
  class_level ClassLevel
  age_range string @description("e.g., 5-6 years")
  term Term
  week int
  duration_mins int @description("Typical lesson duration 35-40 mins")

  // Learning Objectives
  objectives LessonObjective[] @description("3-5 clear, measurable objectives")

  // Lesson Content (shared by pupils and teachers)
  // Structured Lesson Content
  introduction string @description("Opening paragraph introducing the topic. 50-80 words.")
  content_sections ContentSection[] @description("Main lesson sections with headers and sub-points. Total across all sections: Lower Primary 300-350 words, Higher Primary 400-500 words.")
  conclusion string @description("Closing paragraph summarizing key takeaways. 50-80 words.")
  key_points string[] @description("3-5 bullet-point summary statements")

  // Assessment Questions
  mcq_questions MultipleChoiceQuestion[] @description("Exactly 9 questions, answers included for teachers")
  theoretical_questions TheoreticalQuestion[] @description("Exactly 9 questions with model answers for teachers")

  // Teacher-Specific Sections
  prior_knowledge string[] @description("What pupils should know + common misconceptions")
  materials string[] @description("Teaching aids with local alternatives")
  lesson_steps LessonStep[] @description("5 steps covering full lesson flow")
  formative_assessment string @description("Ongoing checks during lesson")
  summative_assessment string @description("End-of-lesson evaluation")
  success_criteria string[] @description("How to measure objective achievement")
  remediation string @description("Support for struggling learners")
  extension_activities string[] @description("For fast learners, homework, projects")

  // References
  primary_sources string[] @description("NERDC curriculum, Ministry guidelines")
  textbook_references string[] @description("Nigerian publishers with page numbers")
  teacher_tips string @description("Age-specific guidance, common difficulties, differentiation strategies. WORD LIMIT: 150-200 words")
}

// ============================================================================
// MAIN GENERATION FUNCTION
// ============================================================================

function GenerateNigerianLesson(
  subject: string,
  class_level: ClassLevel,
  term: Term,
  week: int,
  topic: string,
  age_group: string,
  context: string?
) -> CompleteLessonContent {
  client MainClient

  prompt #"
    Generate comprehensive Nigerian school workbook lesson with ABSOLUTE ACCURACY.
    Output should contain ALL sections for both pupils and teachers in one unified structure.

    CONTEXT
    - Subject: {{ subject }}
    - Class: {{ class_level }}
    - Term: {{ term }}
    - Week: {{ week }}
    - Topic: {{ topic }}
    - Age Group: {{ age_group }}
    - Additional Context Info: {{ context }}

    CRITICAL REQUIREMENTS

    1. Accuracy Standards
    - Base ALL content on: Nigerian National Curriculum, NERDC guides, approved publishers (Macmillan Nigeria, University Press, LearnAfrica, Evans Brothers)
    - NO fabricated facts or hallucinations
    - All examples must use authentic Nigerian contexts
    - Use Ogbomoso locations only when specific places needed

    2. Age-Appropriate Language for Content Section
    {% if class_level == ClassLevel.PRIMARY_1 %}
    - Age 5-6: Very simple sentences, basic vocabulary, concrete familiar concepts only
    - Example: "A ball is round. We can throw a ball."
    {% elif class_level == ClassLevel.PRIMARY_2 %}
    - Age 6-7: Simple sentences, familiar examples, basic explanations
    - Example: "Plants need water to grow. We water plants every day."
    {% elif class_level == ClassLevel.PRIMARY_3 %}
    - Age 7-8: Short paragraphs, more detailed explanations, some abstract ideas
    - Example: "Living things need food, water and air. Plants make their own food using sunlight."
    {% elif class_level == ClassLevel.PRIMARY_4 %}
    - Age 8-9: Structured paragraphs, intermediate vocabulary, abstract concepts introduced
    - Example: "Photosynthesis is the process plants use to make food. Chlorophyll in leaves captures sunlight energy."
    {% elif class_level == ClassLevel.PRIMARY_5 %}
    - Age 9-10: Complex sentences, advanced vocabulary, abstract reasoning
    - Example: "Photosynthesis converts light energy into chemical energy stored in glucose molecules, releasing oxygen as a byproduct."
    {% elif class_level == ClassLevel.JSS_1 %}
    - Age 10-11: Complex sentences, advanced vocabulary, abstract reasoning
    - Example: "Photosynthesis converts light energy into chemical energy stored in glucose molecules, releasing oxygen as a byproduct."
    {% elif class_level == ClassLevel.JSS_2 %}
    - Age 11-12: Complex sentences, advanced vocabulary, abstract reasoning
    - Example: "Photosynthesis converts light energy into chemical energy stored in glucose molecules, releasing oxygen as a byproduct."
    {% elif class_level == ClassLevel.JSS_3 %}
    - Age 12-13: Complex sentences, advanced vocabulary, abstract reasoning
    - Example: "Photosynthesis converts light energy into chemical energy stored in glucose molecules, releasing oxygen as a byproduct."
    {% endif %}

    3. Word Count Limits (STRICT)
    {% if class_level in [ClassLevel.PRIMARY_1, ClassLevel.PRIMARY_2, ClassLevel.PRIMARY_3] %}
    - Main Content: 400-450 words MAX
    - Teacher Tips: 150-200 words
    {% else %}
    - Main Content: 500-600 words MAX
    - Teacher Tips: 150-200 words
    {% endif %}

    4. Formatting Rules
    - Use numbered lists: 1, 2, 3 for main points
    - Use sub-numbering: (i), (ii), (iii) OR (a), (b), (c) for sub-points
    - NEVER use bullet points (•) anywhere
    - Bold only for headers/subtopics, not emphasis

    5. Question Requirements
    - MCQs: Exactly 9, each 1 mark, culturally relevant distractors
    - Include correct_answer and explanation for each MCQ (teachers will see these)
    - Theory: Exactly 9, each 5 marks total, parts (a), (b) if multi-part
    - Include model_answer and marking_scheme for each theory question (teachers will see these)
    - All questions must assess objectives directly

    6. Lesson Steps Structure (5 Required Steps)
    1. INTRODUCTION (5-7 mins): Prior knowledge activation, attention grabber
    2. DEVELOPMENT (15-20 mins): New content presentation, guided practice
    3. GENERALIZATION (5 mins): Connecting to broader concepts
    4. APPLICATION (8-10 mins): Pupils practice independently/groups
    5. CONCLUSION (3-5 mins): Summary, assessment, homework

    7. Nigerian Educational Standards
    - Align with NERDC curriculum frameworks
    - Reference WAEC/NECO syllabi where applicable
    - Include Federal/State Ministry guidelines
    - Use naira (₦) for money examples
    - Use Nigerian locations, names, foods, customs naturally

    OUTPUT NOTES
    - The content field is shared between pupils and teachers (same text appears in both manuals)
    - MCQ and theory questions appear in pupils manual WITHOUT answers
    - Same questions appear in teachers manual WITH answers, explanations, and marking schemes
    - All teacher-specific fields (lesson_steps, prior_knowledge, materials, etc.) are for teachers manual only

    {{ ctx.output_format }}
  "#
}


// ============================================================================
// TEST CASES
// ============================================================================

test primary_2_math_addition {
  functions [GenerateNigerianLesson]
  args {
    subject "Mathematics"
    class_level PRIMARY_2
    term FIRST
    week 3
    topic "Addition of numbers 1-20"
    age_group "6-7 years"
  }
}

test primary_5_science_solar_system {
  functions [GenerateNigerianLesson]
  args {
    subject "Basic Science"
    class_level PRIMARY_5
    term SECOND
    week 8
    topic "The Solar System"
    age_group "9-10 years"
  }
}

test primary_3_english_nouns {
  functions [GenerateNigerianLesson]
  args {
    subject "English Language"
    class_level PRIMARY_3
    term THIRD
    week 5
    topic "Nouns - Common and Proper"
    age_group "7-8 years"
  }
}

test primary_1_basic_science {
  functions [GenerateNigerianLesson]
  args {
    subject "Basic Science"
    class_level PRIMARY_1
    term FIRST
    week 2
    topic "Parts of the body"
    age_group "5-6 years"
  }
}
