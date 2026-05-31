-- ============================================================
-- Test Setup: Schema + Seed for local lesson generation test
-- ============================================================

USE NS main DB johnethel-school-generated-lessons;

-- ============================================================
-- Step 1: Define lookup tables
-- ============================================================

DEFINE TABLE class_levels SCHEMAFULL;
DEFINE FIELD name ON class_levels TYPE string;
DEFINE FIELD code ON class_levels TYPE string;
DEFINE FIELD active ON class_levels TYPE bool DEFAULT true;
DEFINE FIELD age_range ON class_levels TYPE option<string>;
DEFINE INDEX idx_cl_name ON class_levels COLUMNS name UNIQUE;

DEFINE TABLE subjects SCHEMAFULL;
DEFINE FIELD name ON subjects TYPE string;
DEFINE FIELD code ON subjects TYPE string;
DEFINE FIELD active ON subjects TYPE bool;
DEFINE INDEX idx_sub_name ON subjects COLUMNS name UNIQUE;

DEFINE TABLE terms SCHEMAFULL;
DEFINE FIELD name ON terms TYPE string;
DEFINE FIELD sort_order ON terms TYPE int;
DEFINE FIELD active ON terms TYPE bool;
DEFINE INDEX idx_term_name ON terms COLUMNS name UNIQUE;

-- ============================================================
-- Step 2: Define has_subject RELATION edge
-- ============================================================

DEFINE TABLE has_subject TYPE RELATION FROM class_levels TO subjects;
DEFINE FIELD active ON has_subject TYPE bool DEFAULT true;
DEFINE INDEX idx_hs_unique ON has_subject COLUMNS in, out UNIQUE;
DEFINE INDEX idx_hs_in ON has_subject COLUMNS in;

-- ============================================================
-- Step 3: Define lessons table (SCHEMAFULL)
-- ============================================================

DEFINE TABLE lessons SCHEMAFULL;

DEFINE FIELD class_subject ON lessons TYPE record<has_subject> ASSERT $value != NONE;
DEFINE FIELD term          ON lessons TYPE record<terms>        ASSERT $value != NONE;
DEFINE FIELD week          ON lessons TYPE int                  ASSERT $value >= 1;
DEFINE FIELD topic_title   ON lessons TYPE string               ASSERT $value != NONE;
DEFINE FIELD active        ON lessons TYPE bool DEFAULT true;
DEFINE FIELD duration_mins ON lessons TYPE int;

DEFINE FIELD objectives           ON lessons TYPE array<object> FLEXIBLE;
DEFINE FIELD content_sections     ON lessons TYPE array<object> FLEXIBLE;
DEFINE FIELD lesson_steps         ON lessons TYPE array<object> FLEXIBLE;
DEFINE FIELD mcq_questions        ON lessons TYPE array<object> FLEXIBLE;
DEFINE FIELD theoretical_questions ON lessons TYPE array<object> FLEXIBLE;
DEFINE FIELD key_points           ON lessons TYPE array;
DEFINE FIELD materials            ON lessons TYPE array;
DEFINE FIELD prior_knowledge      ON lessons TYPE array;
DEFINE FIELD success_criteria     ON lessons TYPE array;
DEFINE FIELD extension_activities ON lessons TYPE array;
DEFINE FIELD textbook_references  ON lessons TYPE array;
DEFINE FIELD primary_sources      ON lessons TYPE array;

DEFINE FIELD introduction          ON lessons TYPE string;
DEFINE FIELD conclusion            ON lessons TYPE string;
DEFINE FIELD formative_assessment  ON lessons TYPE string;
DEFINE FIELD summative_assessment  ON lessons TYPE string;
DEFINE FIELD remediation           ON lessons TYPE string;
DEFINE FIELD teacher_tips          ON lessons TYPE string;

DEFINE INDEX idx_lessons_nav  ON lessons COLUMNS class_subject, term, week;
DEFINE INDEX idx_lessons_term ON lessons COLUMNS class_subject, term;

-- ============================================================
-- Step 4: Define topics table
-- ============================================================

DEFINE TABLE topics SCHEMAFULL;
DEFINE FIELD agegroup   ON topics TYPE string;
DEFINE FIELD class      ON topics TYPE string;
DEFINE FIELD context    ON topics TYPE string;
DEFINE FIELD subject    ON topics TYPE string;
DEFINE FIELD term       ON topics TYPE string;
DEFINE FIELD topic      ON topics TYPE string;
DEFINE FIELD week       ON topics TYPE int;
DEFINE FIELD generated  ON topics TYPE bool DEFAULT false;

-- ============================================================
-- Step 5: Seed lookup data
-- ============================================================

CREATE class_levels:jss_1 CONTENT {
  name: "Jss 1", code: "jss_1", active: true, age_range: "10-11"
};

CREATE class_levels:jss_2 CONTENT {
  name: "Jss 2", code: "jss_2", active: true, age_range: "11-12"
};

CREATE subjects:computer_studies CONTENT {
  name: "Computer Studies", code: "computer_studies", active: true
};

RELATE class_levels:jss_1 -> has_subject -> subjects:computer_studies CONTENT {
  active: true
};

RELATE class_levels:jss_2 -> has_subject -> subjects:computer_studies CONTENT {
  active: true
};

CREATE terms:noel_term CONTENT {
  name: "Noel Term", sort_order: 1, active: true
};

-- ============================================================
-- Step 6: Seed topics (5 records, generated = false)
-- ============================================================

CREATE type::record("topics", "jss2_computer_scheme_of_work:xbm1dns2yt66w00mg54f") CONTENT {
  agegroup: "11-12",
  class: "Jss 2",
  context: "Identifying and understanding various ways computers and the internet can be misused or abused, and the consequences of such actions",
  subject: "Computer Studies",
  term: "Noel Term",
  topic: "Computer and Internet Misuse",
  week: 9,
  generated: false
};

CREATE type::record("topics", "jss2_computer_scheme_of_work:z4s56eqku7ha2uipykos") CONTENT {
  agegroup: "11-12",
  class: "Jss 2",
  context: "Learning what BASIC stands for (Beginners All-purpose Symbolic Instruction Code), understanding BASIC character set and key statements",
  subject: "Computer Studies",
  term: "Noel Term",
  topic: "Introduction to BASIC Programming",
  week: 5,
  generated: false
};

CREATE type::record("topics", "jss1_computer_studies_scheme_of_work:s349078nlnmomyj67zwe") CONTENT {
  agegroup: "10-11",
  class: "Jss 1",
  context: "Learning the six stages of data processing: data gathering (collecting raw data), data collation (organizing data), input stage (entering data), processing stage (manipulating data), storage stage (saving data), and output stage (presenting results)",
  subject: "Computer Studies",
  term: "Noel Term",
  topic: "Data Processing Cycle - Stages",
  week: 9,
  generated: false
};

CREATE type::record("topics", "jss1_computer_studies_scheme_of_work:ttos5jljabbeuapi9jyf") CONTENT {
  agegroup: "10-11",
  class: "Jss 1",
  context: "Learning about early mechanical tools for counting and calculation including the abacus (ancient calculating tool with beads on rods), slide rule (mechanical calculator), and four-figure tables used for mathematical computations",
  subject: "Computer Studies",
  term: "Noel Term",
  topic: "Mechanical Counting and Calculating Devices",
  week: 2,
  generated: false
};

CREATE type::record("topics", "jss1_computer_studies_scheme_of_work:ucki0v8kftk5s606s8xb") CONTENT {
  agegroup: "10-11",
  class: "Jss 1",
  context: "Introduction to primitive counting methods used before modern computers including using fingers, toes, stones, sticks, pebbles, and cowries to count and represent numbers, understanding the limitations of these methods for large numbers",
  subject: "Computer Studies",
  term: "Noel Term",
  topic: "Early Counting Devices",
  week: 1,
  generated: false
};
