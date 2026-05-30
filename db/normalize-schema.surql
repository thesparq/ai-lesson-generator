-- ============================================================
-- Unit 9 — SurrealDB Schema Normalization
-- Run once in Surrealist's SQL editor.
-- Idempotent: safe to re-run.
-- Does NOT modify or remove existing lesson_content fields.
-- ============================================================

----------------
-- Step 1: Lookup tables (strict schema) + indexes
----------------

DEFINE TABLE subjects SCHEMAFULL;
DEFINE FIELD name ON subjects TYPE string;
DEFINE FIELD code ON subjects TYPE option<string>;
DEFINE FIELD active ON subjects TYPE bool DEFAULT true;
DEFINE INDEX idx_subjects_name ON subjects COLUMNS name UNIQUE;

DEFINE TABLE class_levels SCHEMAFULL;
DEFINE FIELD name ON class_levels TYPE string;
DEFINE FIELD code ON class_levels TYPE option<string>;
DEFINE FIELD active ON class_levels TYPE bool DEFAULT true;
DEFINE INDEX idx_cl_name ON class_levels COLUMNS name UNIQUE;

DEFINE TABLE terms SCHEMAFULL;
DEFINE FIELD name ON terms TYPE string;
DEFINE FIELD sort_order ON terms TYPE int;
DEFINE FIELD active ON terms TYPE bool DEFAULT true;
DEFINE INDEX idx_terms_name ON terms COLUMNS name UNIQUE;

-- Junction table for class ↔ subject mapping
DEFINE TABLE class_subjects SCHEMAFULL;
DEFINE FIELD class_level_id ON class_subjects TYPE record<class_levels>;
DEFINE FIELD subject_id ON class_subjects TYPE record<subjects>;
DEFINE FIELD active ON class_subjects TYPE bool DEFAULT true;
DEFINE INDEX idx_cs_unique ON class_subjects COLUMNS class_level_id, subject_id UNIQUE;

----------------
-- Step 2: Add FK fields to existing lesson_content (schemaless stays)
----------------

DEFINE FIELD class_level_id ON lesson_content TYPE option<record<class_levels>>;
DEFINE FIELD subject_id ON lesson_content TYPE option<record<subjects>>;
DEFINE FIELD term_id ON lesson_content TYPE option<record<terms>>;
DEFINE FIELD week_number ON lesson_content TYPE option<int>;

DEFINE INDEX idx_lesson_cl   ON lesson_content COLUMNS class_level_id;
DEFINE INDEX idx_lesson_subj ON lesson_content COLUMNS subject_id;
DEFINE INDEX idx_lesson_nav  ON lesson_content COLUMNS class_level_id, subject_id, term_id, week_number;

----------------
-- Step 3: Populate subjects (idempotent — uses array::distinct)
----------------

LET $subjects = array::distinct((SELECT VALUE subject FROM lesson_content));
FOR $s IN $subjects {
    UPSERT subjects CONTENT { name: $s, active: true };
};

----------------
-- Step 4: Populate class_levels (idempotent — uses array::distinct)
----------------

LET $levels = array::distinct((SELECT VALUE class_level FROM lesson_content));
FOR $l IN $levels {
    UPSERT class_levels CONTENT { name: $l, active: true };
};

----------------
-- Step 5: Populate terms (idempotent — uses array::distinct)
----------------

LET $terms = array::distinct((SELECT VALUE term FROM lesson_content));
FOR $t IN $terms {
    LET $order = IF $t = 'First Term' THEN 1
                 ELSE IF $t = 'Second Term' THEN 2
                 ELSE IF $t = 'Third Term' THEN 3
                 ELSE 0
                 END;

    UPSERT terms:[$t] CONTENT { name: $t, sort_order: $order, active: true };
};

----------------
-- Step 6: Populate class_subjects (idempotent)
----------------

LET $pairs = array::distinct(SELECT class_level, subject FROM lesson_content);
FOR $p IN $pairs {
    LET $cl_id = (SELECT VALUE id FROM class_levels WHERE name = $p.class_level LIMIT 1)[0];
    LET $s_id  = (SELECT VALUE id FROM subjects WHERE name = $p.subject LIMIT 1)[0];

    IF $cl_id != NONE AND $s_id != NONE {
        UPSERT class_subjects:[$cl_id, $s_id] CONTENT {
            class_level_id: $cl_id,
            subject_id: $s_id,
            active: true
        };
    };
};

----------------
-- Step 7: Update lesson_content with FK references + week number
----------------

UPDATE lesson_content SET
    subject_id     = (SELECT VALUE id FROM subjects     WHERE name = $parent.subject     LIMIT 1)[0],
    class_level_id = (SELECT VALUE id FROM class_levels WHERE name = $parent.class_level LIMIT 1)[0],
    term_id        = (SELECT VALUE id FROM terms        WHERE name = $parent.term        LIMIT 1)[0],
    week_number    = IF $parent.week != NONE THEN
                        IF type::is::int($parent.week) THEN
                            $parent.week
                        ELSE
                            type::int(string::trim(string::replace($parent.week, 'Week', '')))
                        END
                     ELSE
                        NONE
                     END;

----------------
-- Verification queries
----------------

-- 1. Check lookup tables populated correctly
SELECT count() FROM subjects GROUP ALL;
SELECT count() FROM class_levels GROUP ALL;
SELECT count() FROM terms GROUP ALL;
SELECT count() FROM class_subjects GROUP ALL;

-- 2. Spot check the actual records
SELECT * FROM subjects;
SELECT * FROM class_levels;
SELECT * FROM terms ORDER BY sort_order;

-- 3. Check for lesson_content records missing any of the new foreign key fields
SELECT id, subject, class_level, term, week
FROM lesson_content
WHERE subject_id = NONE
   OR class_level_id = NONE
   OR term_id = NONE;

-- 4. Check week_number parsing — find any where week exists but week_number is NONE
SELECT id, week, week_number
FROM lesson_content
WHERE week != NONE AND week_number = NONE;

-- 5. Sanity check week_number values look reasonable
SELECT math::min(week_number) AS min_week, math::max(week_number) AS max_week
FROM lesson_content
WHERE week_number != NONE
GROUP ALL;

-- 6. Verify class_subjects covers all pairs in lesson_content
LET $lc_pairs = array::distinct(SELECT class_level_id, subject_id FROM lesson_content WHERE class_level_id != NONE AND subject_id != NONE);
LET $cs_pairs = array::distinct(SELECT class_level_id, subject_id FROM class_subjects);
RETURN {
    lesson_content_pairs: array::len($lc_pairs),
    class_subjects_pairs: array::len($cs_pairs)
};

-- 7b. Add class_subject_id FK, update nav index, drop deprecated indexes
DEFINE FIELD class_subject_id ON lesson_content TYPE option<record<class_subjects>>;
DEFINE INDEX idx_lesson_cs ON lesson_content COLUMNS class_subject_id;
UPDATE lesson_content SET
  class_subject_id = (
    SELECT VALUE id FROM class_subjects
    WHERE class_level_id = $parent.class_level_id
      AND subject_id = $parent.subject_id
    LIMIT 1
  )[0];
-- Update nav index to use class_subject_id
DEFINE INDEX idx_lesson_nav ON lesson_content COLUMNS class_subject_id, term_id, week_number;
-- Drop deprecated indexes
REMOVE INDEX idx_lesson_cl ON lesson_content;
REMOVE INDEX idx_lesson_subj ON lesson_content;

-- 7. Check foreign keys actually resolve (no orphaned references)
SELECT id, subject_id, subject_id.name AS resolved_subject
FROM lesson_content
WHERE subject_id != NONE
LIMIT 5;

SELECT id, class_level_id, class_level_id.name AS resolved_class_level
FROM lesson_content
WHERE class_level_id != NONE
LIMIT 5;

SELECT id, term_id, term_id.name AS resolved_term, term_id.sort_order AS sort_order
FROM lesson_content
WHERE term_id != NONE
LIMIT 5;
