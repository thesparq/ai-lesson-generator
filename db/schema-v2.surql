-- ============================================================
-- HF-01 — SurrealDB Schema v2
-- Idiomatic graph/document schema for lesson data.
-- Idempotent: safe to re-run.
-- Does NOT modify or remove lesson_content (deprecated).
-- ============================================================

----------------
-- Step 0: Clear existing data (table schemas stay)
-- Order matters: child records before referenced records.
----------------

DELETE lessons;
DELETE has_subject;
DELETE class_levels;
DELETE subjects;
DELETE terms;

----------------
-- Step 1a: Populate subjects (idempotent)
----------------

LET $subjects = array::distinct((SELECT VALUE subject FROM lesson_content));
FOR $s IN $subjects {
    LET $slug = string::lowercase(string::replace($s, ' ', '_'));
    LET $id = type::thing("subjects", $slug);
    CREATE $id CONTENT { name: $s, code: $slug, active: true };
};

----------------
-- Step 1b: Populate class_levels with formatted names
-- PRIMARY_N → "Year N" (ID year_N)
-- JSS_N → "JSS N" (ID stays jss_N)
----------------

LET $levels = array::distinct((SELECT VALUE class_level FROM lesson_content));
FOR $l IN $levels {
    LET $label = IF string::starts_with($l, 'PRIMARY_') THEN
        "Year " + string::replace($l, 'PRIMARY_', '')
    ELSE IF string::starts_with($l, 'JSS_') THEN
        string::replace($l, '_', ' ')
    ELSE
        $l
    END;
    LET $slug = string::lowercase(string::replace($label, ' ', '_'));
    LET $id = type::thing("class_levels", $slug);
    LET $age = (SELECT VALUE age_range FROM lesson_content
                WHERE class_level = $l AND age_range != NONE LIMIT 1)[0];
    CREATE $id CONTENT {
        name: $label,
        code: $slug,
        active: true,
        age_range: $age
    };
};

----------------
-- Step 1c: Populate terms (idempotent)
----------------

LET $terms = array::distinct((SELECT VALUE term FROM lesson_content));
FOR $t IN $terms {
    LET $order = IF $t = 'First Term' THEN 1
                 ELSE IF $t = 'Second Term' THEN 2
                 ELSE IF $t = 'Third Term' THEN 3
                 ELSE 0
                 END;
    LET $slug = string::lowercase(string::replace($t, ' ', '_'));
    LET $id = type::thing("terms", $slug);
    CREATE $id CONTENT { name: $t, sort_order: $order, active: true };
};

----------------
-- Step 1d: Update lookup table schemas
----------------

DEFINE FIELD age_range ON class_levels TYPE option<string>;
DEFINE INDEX idx_cl_name ON class_levels COLUMNS name UNIQUE;

----------------
-- Step 2: Create has_subject graph edge (replaces class_subjects)
-- Reads directly from lesson_content (not the class_subjects table)
----------------

REMOVE TABLE has_subject;
DEFINE TABLE has_subject TYPE RELATION FROM class_levels TO subjects;
DEFINE FIELD active ON has_subject TYPE bool DEFAULT true;
DEFINE INDEX idx_hs_unique ON has_subject COLUMNS in, out UNIQUE;
DEFINE INDEX idx_hs_in ON has_subject COLUMNS in;

LET $pairs = array::distinct(SELECT class_level, subject FROM lesson_content);
FOR $p IN $pairs {
    LET $cl_label = IF string::starts_with($p.class_level, 'PRIMARY_') THEN
        "Year " + string::replace($p.class_level, 'PRIMARY_', '')
    ELSE IF string::starts_with($p.class_level, 'JSS_') THEN
        string::replace($p.class_level, '_', ' ')
    ELSE
        $p.class_level
    END;
    LET $cl_id = (SELECT VALUE id FROM class_levels WHERE name = $cl_label LIMIT 1)[0];
    LET $s_id = (SELECT VALUE id FROM subjects WHERE name = $p.subject LIMIT 1)[0];
    IF $cl_id != NONE AND $s_id != NONE {
        RELATE $cl_id -> has_subject -> $s_id CONTENT { active: true };
    };
};

----------------
-- Step 3: Create lessons table (replaces lesson_content)
----------------

REMOVE TABLE lessons;

DEFINE TABLE lessons SCHEMAFULL;

DEFINE FIELD class_subject ON lessons TYPE record<has_subject> ASSERT $value != NONE;
DEFINE FIELD term          ON lessons TYPE record<terms>        ASSERT $value != NONE;
DEFINE FIELD week          ON lessons TYPE int                  ASSERT $value >= 1;
DEFINE FIELD topic_title   ON lessons TYPE string               ASSERT $value != NONE;
DEFINE FIELD active        ON lessons TYPE bool DEFAULT true;
DEFINE FIELD duration_mins ON lessons TYPE int;

DEFINE FIELD objectives           ON lessons FLEXIBLE TYPE array<object>;
DEFINE FIELD content_sections     ON lessons FLEXIBLE TYPE array<object>;
DEFINE FIELD key_points           ON lessons FLEXIBLE TYPE array;
DEFINE FIELD lesson_steps         ON lessons FLEXIBLE TYPE array<object>;
DEFINE FIELD mcq_questions        ON lessons FLEXIBLE TYPE array<object>;
DEFINE FIELD theoretical_questions ON lessons FLEXIBLE TYPE array<object>;
DEFINE FIELD materials            ON lessons FLEXIBLE TYPE array;
DEFINE FIELD prior_knowledge      ON lessons FLEXIBLE TYPE array;
DEFINE FIELD success_criteria     ON lessons FLEXIBLE TYPE array;
DEFINE FIELD extension_activities ON lessons FLEXIBLE TYPE array;
DEFINE FIELD textbook_references  ON lessons FLEXIBLE TYPE array;
DEFINE FIELD primary_sources      ON lessons FLEXIBLE TYPE array;

DEFINE FIELD introduction          ON lessons TYPE string;
DEFINE FIELD conclusion            ON lessons TYPE string;
DEFINE FIELD formative_assessment  ON lessons TYPE string;
DEFINE FIELD summative_assessment  ON lessons TYPE string;
DEFINE FIELD remediation           ON lessons TYPE string;
DEFINE FIELD teacher_tips          ON lessons TYPE string;

DEFINE INDEX idx_lessons_nav  ON lessons COLUMNS class_subject, term, week;
DEFINE INDEX idx_lessons_term ON lessons COLUMNS class_subject, term;

----------------
-- Diagnostic: check raw array field format in lesson_content
----------------

SELECT class_level, subject, term,
       type::is::string(objectives) AS objectives_is_string,
       type::is::array(objectives)  AS objectives_is_array,
       type::is::string(content_sections) AS cs_is_string,
       type::is::string(lesson_steps) AS ls_is_string,
       type::is::string(mcq_questions) AS mcq_is_string,
       type::is::string(key_points) AS kp_is_string,
       objectives, content_sections
FROM lesson_content
LIMIT 3;

----------------
-- Step 4: Migrate lesson_content → lessons
----------------

LET $old = SELECT * FROM lesson_content;
FOR $lc IN $old {
    LET $cl_label = IF string::starts_with($lc.class_level, 'PRIMARY_') THEN
        "Year " + string::replace($lc.class_level, 'PRIMARY_', '')
    ELSE IF string::starts_with($lc.class_level, 'JSS_') THEN
        string::replace($lc.class_level, '_', ' ')
    ELSE
        $lc.class_level
    END;
    LET $cl_id = (SELECT VALUE id FROM class_levels WHERE name = $cl_label LIMIT 1)[0];
    LET $sb_id = (SELECT VALUE id FROM subjects WHERE name = $lc.subject LIMIT 1)[0];
    LET $hs = (SELECT VALUE id FROM has_subject WHERE in = $cl_id AND out = $sb_id LIMIT 1)[0];
    LET $resolved_term = (SELECT VALUE id FROM terms WHERE name = $lc.term LIMIT 1)[0];
    IF $hs != NONE AND $resolved_term != NONE {
        CREATE lessons CONTENT {
            class_subject: $hs,
            term: $resolved_term,
            week: $lc.week_number ?? 1,
            topic_title: $lc.topic_title ?? ($lc.subject ?? ""),
            active: $lc.active ?? true,
            duration_mins: $lc.duration_mins ?? 40,
            introduction: $lc.introduction,
            conclusion: $lc.conclusion,
            objectives: $lc.objectives ?? [],
            content_sections: $lc.content_sections ?? [],
            key_points: $lc.key_points ?? [],
            lesson_steps: $lc.lesson_steps ?? [],
            mcq_questions: $lc.mcq_questions ?? [],
            theoretical_questions: $lc.theoretical_questions ?? [],
            materials: $lc.materials ?? [],
            prior_knowledge: $lc.prior_knowledge ?? [],
            success_criteria: $lc.success_criteria ?? [],
            extension_activities: $lc.extension_activities ?? [],
            textbook_references: $lc.textbook_references ?? [],
            primary_sources: $lc.primary_sources ?? [],
            formative_assessment: $lc.formative_assessment ?? "",
            summative_assessment: $lc.summative_assessment ?? "",
            remediation: $lc.remediation ?? "",
            teacher_tips: $lc.teacher_tips ?? ""
        };
    };
};

----------------
-- Verification queries
----------------

SELECT count() FROM lessons GROUP ALL;
SELECT count() FROM has_subject GROUP ALL;

SELECT id, class_subject.in.name AS class_name,
       class_subject.out.name AS subject_name,
       term.name AS term_name,
       week,
       topic_title
FROM lessons
LIMIT 10;

SELECT math::min(week) AS min_week, math::max(week) AS max_week
FROM lessons
GROUP ALL;

LET $lesson_pairs = array::distinct(
    SELECT class_subject.in.id AS cl_id, class_subject.out.id AS sub_id
    FROM lessons
);
LET $edge_pairs = array::distinct(
    SELECT in.id AS cl_id, out.id AS sub_id
    FROM has_subject
);
RETURN {
    lesson_pairs: array::len($lesson_pairs),
    edge_pairs: array::len($edge_pairs),
    all_covered: $lesson_pairs = $edge_pairs
};

SELECT count() FROM lesson_content GROUP ALL;
SELECT id, class_level, subject, term, week
FROM lesson_content
LIMIT 5;
