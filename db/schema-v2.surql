-- ============================================================
-- HF-01 — SurrealDB Schema v2
-- Idiomatic graph/document schema for lesson data.
-- Idempotent: safe to re-run.
-- Does NOT modify or remove lesson_content (deprecated).
-- ============================================================

----------------
-- Step 1: Update lookup tables with new fields
-- (Tables were created by Unit 9 normalize-schema.surql)
----------------

-- Remove active from class_levels (value objects don't toggle)
REMOVE FIELD active ON class_levels;
DEFINE FIELD age_range ON class_levels TYPE option<string>;

-- Remove active from subjects (value objects don't toggle)
REMOVE FIELD active ON subjects;

----------------
-- Step 2: Create has_subject graph edge (replaces class_subjects)
----------------

DEFINE TABLE has_subject TYPE RELATION FROM class_levels TO subjects;
DEFINE FIELD active ON has_subject TYPE bool DEFAULT true;
DEFINE INDEX idx_hs_unique ON has_subject COLUMNS in, out UNIQUE;
DEFINE INDEX idx_hs_in ON has_subject COLUMNS in;

-- Migrate edges from old class_subjects (idempotent — skips existing pairs)
LET $edges = SELECT * FROM class_subjects;
FOR $e IN $edges {
    LET $existing = (SELECT VALUE id FROM has_subject
        WHERE in = $e.class_level_id AND out = $e.subject_id
        LIMIT 1)[0];
    IF $existing == NONE {
        CREATE has_subject CONTENT {
            in: $e.class_level_id,
            out: $e.subject_id,
            active: $e.active
        };
    };
};

----------------
-- Step 3: Create lessons table (replaces lesson_content)
----------------

DEFINE TABLE lessons SCHEMAFULL;

-- Navigation fields (strict typing with ASSERTS)
DEFINE FIELD class_subject ON lessons TYPE record<has_subject> ASSERT $value != NONE;
DEFINE FIELD term          ON lessons TYPE record<terms>        ASSERT $value != NONE;
DEFINE FIELD week          ON lessons TYPE int                  ASSERT $value >= 1;
DEFINE FIELD topic_title   ON lessons TYPE string               ASSERT $value != NONE;
DEFINE FIELD active        ON lessons TYPE bool DEFAULT true;
DEFINE FIELD duration_mins ON lessons TYPE int;

-- Content arrays (loose — app-layer validation)
DEFINE FIELD objectives           ON lessons TYPE array;
DEFINE FIELD content_sections     ON lessons TYPE array;
DEFINE FIELD key_points           ON lessons TYPE array;
DEFINE FIELD lesson_steps         ON lessons TYPE array;
DEFINE FIELD mcq_questions        ON lessons TYPE array;
DEFINE FIELD theoretical_questions ON lessons TYPE array;
DEFINE FIELD materials            ON lessons TYPE array;
DEFINE FIELD prior_knowledge      ON lessons TYPE array;
DEFINE FIELD success_criteria     ON lessons TYPE array;
DEFINE FIELD extension_activities ON lessons TYPE array;
DEFINE FIELD textbook_references  ON lessons TYPE array;

-- String content fields
DEFINE FIELD introduction          ON lessons TYPE string;
DEFINE FIELD conclusion            ON lessons TYPE string;
DEFINE FIELD formative_assessment  ON lessons TYPE string;
DEFINE FIELD summative_assessment  ON lessons TYPE string;
DEFINE FIELD remediation           ON lessons TYPE string;
DEFINE FIELD teacher_tips          ON lessons TYPE string;

-- Navigation indexes
DEFINE INDEX idx_lessons_nav  ON lessons COLUMNS class_subject, term, week;
DEFINE INDEX idx_lessons_term ON lessons COLUMNS class_subject, term;

----------------
-- Step 4: Migrate lesson_content → lessons (idempotent)
-- Skips if a lesson already exists for this class_subject + term + week.
---------------

LET $old = SELECT * FROM lesson_content;
FOR $lc IN $old {
    LET $hs = (SELECT VALUE id FROM has_subject
        WHERE in = $lc.class_level_id AND out = $lc.subject_id
        LIMIT 1)[0];

    IF $hs != NONE AND $lc.term_id != NONE {
        LET $existing = (SELECT VALUE id FROM lessons
            WHERE class_subject = $hs
              AND term = $lc.term_id
              AND week = ($lc.week_number ?? 1)
              AND topic_title = ($lc.topic_title ?? ($lc.subject ?? ""))
            LIMIT 1)[0];
        IF $existing == NONE {
            CREATE lessons CONTENT {
            class_subject: $hs,
            term: $lc.term_id,
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
            formative_assessment: $lc.formative_assessment ?? "",
            summative_assessment: $lc.summative_assessment ?? "",
            remediation: $lc.remediation ?? "",
            teacher_tips: $lc.teacher_tips ?? ""
            };
        };
    };
};

----------------
-- Step 5: Migrate age_range to class_levels (idempotent)
----------------

UPDATE class_levels SET age_range = (
    SELECT VALUE age_range FROM lesson_content
    WHERE class_level = $parent.name AND age_range != NONE
    LIMIT 1
) WHERE age_range IS NONE;

----------------
-- Verification queries
----------------

-- 1. Check record counts
SELECT count() FROM lessons GROUP ALL;
SELECT count() FROM has_subject GROUP ALL;

-- 2. Spot check migrated lessons
SELECT id, class_subject.in.name AS class_name,
       class_subject.out.name AS subject_name,
       term.name AS term_name,
       week,
       topic_title
FROM lessons
LIMIT 10;

-- 3. Verify week values are reasonable
SELECT math::min(week) AS min_week, math::max(week) AS max_week
FROM lessons
GROUP ALL;

-- 4. Verify has_subject edges cover all class-subject pairs in lessons
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

-- 5. Verify lesson_content is untouched
SELECT count() FROM lesson_content GROUP ALL;
SELECT id, class_level, subject, term, week
FROM lesson_content
LIMIT 5;
