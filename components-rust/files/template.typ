// --- NEW CONFIG ---
// --- CONFIGURATION FROM INPUT ---
#import sys: inputs

#let mode = inputs.at("mode", default: "pupil")
#let subject_name = inputs.at("subject_name", default: "")
#let class_year = inputs.at("class_year", default: "YEAR 1")
#let dummy_lessons = inputs.at("lessons", default: ())
#let watermark_image = inputs.at("watermark_image", default: none)

// --- TEMPLATE DEFINITION ---
#let project(
  subject: "",
  year: "",
  mode: "pupil",
  lessons: (),
  header_image: none,
  watermark_image: none,
) = {
  // 1. STYLES & WATERMARK
  set document(title: subject + " Manual", author: "Johnethel School")
  set text(font: "Times New Roman", size: 12pt)
  set par(justify: true)

  // Overlay function
  let overlay(img, color) = layout(bounds => {
    let size = measure(img, ..bounds)
    img
    place(center + horizon, block(..size, fill: color))
  })

  set page(
    paper: "a4",
    margin: (x: 0.8in, y: 1in),
    background: context {
      if watermark_image != none {
        // place(center + center,
        //   block(
        //     fill: white.transparentize(100%),
        //     image(watermark_image, width: 80%),
        //   )
        // )
        overlay(image(watermark_image, width: 80%), white.transparentize(5%))
      } else {
        place(center + horizon, rotate(-45deg, text(100pt, fill: gray.lighten(85%), weight: "bold")[JOHNETHEL]))
      }
    },
  )

  // 2. HELPER: FULL-PAGE RULED LINES
  let full_page_lines(title: none) = context {
    // pagebreak(weak: true)
    if title != none {
      align(center, heading(level: 2, outlined: false)[#upper(title)])
      linebreak()
      v(0.5em)
    } else {
      linebreak()
    }
    layout(size => {
      let remaining = size.height - 0.8in
      let line-spacing = 0.8cm
      // Calculate how many lines actually fit
      let count = calc.floor(remaining / line-spacing)
      block(width: 100%, height: remaining, stroke: none)[
        #stack(
          dir: ttb,
          spacing: line-spacing,
          ..range(count + 2).map(_ => line(length: 100%, stroke: 0.7pt + black)),
        )
      ]
    })
  }

  // Fill remaining space on current page with lines
  let remaining_page_lines(title: none) = context {
    if title != none {
      align(center, heading(level: 2, outlined: false)[#upper(title)])
      v(0.5em)
    }
    let pos = here().position().y
    let page-h = page.height
    let remaining = page-h - pos - 1.6in // subtract bottom margin
    let spacing = calc.floor(remaining / 0.8cm)
    block(width: 100%, height: remaining, stroke: none)[
      #stack(
        dir: ttb,
        spacing: 0.8cm,
        ..range(spacing + 2).map(_ => line(length: 100%, stroke: 0.7pt + black)),
      )
    ]
  }

  // Smart activity pages based on year and remaining space
  let add_activity_pages(year_num: 1) = {
    layout(size => {
      let page_height = size.height
      let current_y = here().position().y
      let remaining = page_height - current_y - 0.8in
      let remaining_percentage = remaining / page_height

      // Determine threshold: if less than 50% remains, it's "few lines"
      let is_few_lines_remaining = remaining_percentage < 0.5

      if year_num <= 2 {
        // Years 1-2: Minimum 1 page, Maximum 1.5 pages
        if is_few_lines_remaining {
          // Few lines remaining: fill current page + add 1 full page
          remaining_page_lines(title: "CLASS ACTIVITIES")
          full_page_lines()
        } else {
          // Lots of space remaining: just fill current page
          remaining_page_lines(title: "CLASS ACTIVITIES")
        }
      } else {
        // Years 3-5: Minimum 1.5 pages, Maximum 2 pages
        if is_few_lines_remaining {
          // Few lines remaining: fill current page + add 2 full pages
          remaining_page_lines(title: "CLASS ACTIVITIES")
          full_page_lines()
          full_page_lines()
        } else {
          // Lots of space remaining: fill current page + add 1 full page
          remaining_page_lines(title: "CLASS ACTIVITIES")
          full_page_lines()
        }
      }
    })
  }


  // 3. FRONT MATTER
  set page(numbering: "i", footer: context { align(center, text(10pt)[#counter(page).display("i")]) })

  align(center + horizon)[
    #text(22pt, weight: "bold")[Copyright Page] \ \ \
    #text(18pt, weight: "bold")[JOHNETHEL SCHOOL MANUAL SERIES] \
    #upper(subject) (#year) \ \ \ \
    #text(
      12pt,
    )[No part of this publication may be reproduced, distributed, or transmitted in any form or by any means, including photocopying, recording, or other electronic or mechanical methods, without the prior written permission of Johnethel School, except in the case of brief quotations embodied in critical reviews and certain other non-commercial uses permitted by copyright law.] \ \ \
    #text(12pt)[*Published by:* Johnethel School \
      *First Edition:* 2025 \
      *Second Edition:* 2026
    ] \ \ \ \
    #text(12pt)[For permission requests, write to: Johnethel School \
      Address: Omolabake House, beside Town Planning Office, Oke Anu, 		     Ogbomoso, Oyo State, Nigeria
      Email: johnethelschool1\@gmail.com \
      Phone: 08036674624, 09039465940
    ] \ \ \ \ \
    #text(
      12pt,
    )[*Attributions:* Cover design includes 3D icons from vecteezy.com. Portions of this work were created with the assistance of an LLM.] \ \ \ \ \ \ \
    #text(
      12pt,
    )[*Disclaimer:* _The information contained in this manual is for educational purposes only. Johnethel School makes every effort to ensure the accuracy of the content but accepts no responsibility for any errors or omissions._]
  ]
  pagebreak()

  align(center + horizon)[
    #text(22pt, weight: "bold")[Instructions for Use] \ \
    #align(left)[#text(15pt)[
      *For Teachers* \
      •	Use the manual as your primary teaching guide during lessons \
      •	Follow the lesson aims and objectives provided in each section \
      •	Assign homework from any section based on your teaching progress \
      •	Record homework assignments in pupils' homework communication books \
      •	Monitor pupil progress through practice questions and activities \
      •	Ensure pupils have necessary materials: pencils, pens, colours, rulers, etc. \
    ]] \
    #align(left)[#text(15pt)[
      *For Parents/Guardians* \
      •	Provide a quiet, well-lit study space for homework \
      •	Allow 15-20 minutes for homework sessions \
      •	Help your child read instructions when needed \
      •	Guide without giving direct answers \
      •	Check and sign completed work in the homework communication book \
      •	Contact school management if you have concerns about your child's progress \
    ]] \
    #align(left)[#text(15pt)[
      *For Pupils/Students* \ \
      *At School:* \
      •	Listen carefully to your teacher's instructions \
      •	Keep your manual clean and tidy \
      •	Complete activities neatly \
      •	Ask questions when you don't understand \ \ \
      *At Home:* \
      •	Find a quiet place for homework \
      •	Read questions slowly \
      •	Write answers clearly \
      •	Complete work assigned by your teacher \
      •	Ask your parents for help if needed \
    ]]
  ]

  pagebreak()

  heading(outlined: false)[Table of Contents]
  outline(title: none, indent: 1.5em)
  pagebreak()

  // 4. MAIN CONTENT
  counter(page).update(1)
  set page(
    numbering: "1",
    header: context {
      block(width: 100%, stroke: (bottom: 0.5pt), inset: (bottom: 8pt))[
        #set text(size: 10pt, weight: "bold")
        #if header_image != none {
          image(header_image, width: 100%)
          v(-0.5em)
        }
        JOHNETHEL #upper(subject) MANUAL (#year) #h(1fr) #text(style: "italic")[Grooming Future Leaders for Excellence]
      ]
    },
    footer: context { align(center, text(10pt)[#counter(page).display("1")]) },
  )

  let last_term = none

  for lesson in lessons {
    // CA Test Logic (Triggered before new term separator)
    if last_term != none and lesson.term != last_term and mode == "pupil" {
      for n in range(4) {
        full_page_lines(title: last_term + " TERM: CA TEST " + str(n + 1))
      }
    }

    // Term Separator
    if lesson.term != last_term {
      pagebreak(weak: true)
      set page(header: none)
      align(center + horizon)[
        #set text(size: 32pt, weight: "bold")
        #heading(level: 1)[#upper(str(lesson.term)) TERM]
      ]
      pagebreak()
      last_term = lesson.term
    }

    // --- LESSON HEADER ---
    heading(level: 1)[TOPIC #lesson.week: #upper(lesson.topic_title)]

    heading(level: 2)[LESSON OBJECTIVES]
    list(..lesson.objectives.map(it => [#it.objective (#it.taxonomy_level)]))

    if mode == "teacher" {
      heading(level: 2)[PUPILS' PREVIOUS KNOWLEDGE]
      list(..lesson.prior_knowledge.map(it => [#it]))
    }

    if mode == "teacher" {
      heading(level: 2)[INSTRUCTIONAL MATERIALS]
      list(..lesson.materials.map(it => [#it]))
    }

    if mode == "teacher" {
      heading(level: 2)[TEACHER PREPARATION]
      [*Materials:* #lesson.materials.join(", ")]
      linebreak()
      [*Duration:* #lesson.duration_mins mins]
    }

    heading(level: 2)[LESSON CONTENT]
    [#lesson.introduction]
    for sec in lesson.content_sections {
      block()[
        *#sec.header*
        #par(sec.body)
        #if sec.sub_points != none {
          for sp in sec.sub_points {
            // Handling potential string or dictionary for .text
            let content = if type(sp.text) == dictionary { sp.text.body } else { sp.text }
            [- #sp.sub_number. #content]
          }
        }
      ]
      v(0.5em)
    }
    [*CONCLUSION*]
    linebreak()
    [#lesson.conclusion]

    heading(level: 2)[Key Points:]
    enum(..lesson.key_points)

    if mode == "teacher" and lesson.lesson_steps != none and lesson.lesson_steps.len() > 0 {
      heading(level: 2)[LESSON STEPS]
      table(
        columns: (auto, 1fr, 1.5fr, 1.5fr),
        fill: (col, row) => if row == 0 { silver.lighten(60%) },
        [*Step*], [*Phase*], [*Teacher Actions*], [*Pupil Activities*],
        ..lesson.lesson_steps.map(s => (str(s.step_number), s.phase, s.teacher_actions, s.pupil_activities)).flatten(),
      )
    }

    if mode == "teacher" {
      heading(level: 2)[FORMATIVE ASSESSMENT]
      [#lesson.formative_assessment]
    }

    if mode == "teacher" {
      heading(level: 2)[SUMMATIVE ASSESSMENT]
      [#lesson.summative_assessment]
    }

    if mode == "teacher" {
      heading(level: 2)[SUCCESS CRITERIA]
      list(..lesson.success_criteria.map(it => [#it]))
    }

    if mode == "pupil" or mode == "teacher" {
      if lesson.mcq_questions.len() > 0 {
        heading(level: 2)[REVISION QUESTIONS (Multiple Choice)]
        let q_count = 1
        for q in lesson.mcq_questions {
          if q_count > 5 {
            break
          }
          [#q_count. #q.question ]
          [(a) #q.option_a (b) #q.option_b (c) #q.option_c]
          if mode == "teacher" {
            text(fill: blue, weight: "bold")[ [Ans: #q.correct_answer] \ Explanation: #q.explanation]
          }
          v(0.5em)
          q_count += 1
        }
      }
    }

    if mode == "pupil" or mode == "teacher" {
      if lesson.theoretical_questions.len() > 0 {
        heading(level: 2)[THEORETICAL QUESTIONS]
        let q_count = 1
        for q in lesson.theoretical_questions {
          if q_count > 5 {
            break
          }
          [#q_count. #q.question \ ]
          for part in q.parts {
            [#part ]
            linebreak()
          }
          // [(a) #q.option_a (b) #q.option_b (c) #q.option_c]
          if mode == "teacher" { text(fill: blue, weight: "bold")[ Ans:\  #q.model_answer] }
          v(0.5em)
          q_count += 1
        }
      }
    }


    if mode == "teacher" {
      heading(level: 2)[EXTENSION ACTIVITIES]
      list(..lesson.extension_activities.map(it => [#it]))
    }

    if mode == "teacher" {
      heading(level: 2)[REMEDIATION (Support for struggling learners)]
      [#lesson.remediation]
    }

    if mode == "teacher" {
      heading(level: 2)[REFERENCES]
      list(..lesson.textbook_references.map(it => [#it]))
    }

    // Activity Pages
    if mode == "pupil" {
      let year_num = int(year.split(" ").last())
      add_activity_pages(year_num: year_num)
      // remaining_page_lines(title: "CLASS ACTIVITIES")
      // full_page_lines()
    }

    pagebreak(weak: true)
  }

  // Final Term CA Test
  if mode == "pupil" and last_term != none {
    for n in range(4) {
      full_page_lines(title: last_term + " TERM: CA TEST " + str(n + 1))
    }
  }

  // let question_bank_last_term = none
  // heading(level: 2)[EXAM QUESTIONS BANK]
  // heading(level: 3)[REVISION QUESTIONS (Multiple Choice)]
  // let objective_q_number = 1
  // for lesson in lessons {
  //   // term separator
  //   if lesson.term != question_bank_last_term {
  //     heading(level: 3)[#lesson.term]
  //     question_bank_last_term = lesson.term
  //   }
  //   if mode == "teacher" {
  //     if lesson.mcq_questions.len() > 0 {
  //       let index = 0
  //       for q in lesson.mcq_questions {
  //         if index < 5 {
  //           index += 1
  //           continue
  //         }
  //         [#objective_q_number. #q.question ]
  //         [(a) #q.option_a (b) #q.option_b (c) #q.option_c]
  //         text(fill: blue, weight: "bold")[ [Ans: #q.correct_answer] \ Explanation: #q.explanation]
  //         v(0.5em)
  //         index += 1
  //         objective_q_number += 1
  //       }
  //     }
  //   }
  // }

  // heading(level: 3)[THEORETICAL QUESTIONS]
  // let essay_q_number = 1
  // for lesson in lessons {
  //   if mode == "teacher" {
  //     if lesson.theoretical_questions.len() > 0 {
  //       let index = 0
  //       for q in lesson.theoretical_questions {
  //         if index < 5 {
  //           index += 1
  //           continue
  //         }
  //         [#q_number. #q.question \ ]
  //         for part in q.parts {
  //           [#part ]; linebreak()
  //         }
  //         // [(a) #q.option_a (b) #q.option_b (c) #q.option_c]
  //         if mode == "teacher" { text(fill: blue, weight: "bold")[ Ans:\  #q.model_answer] }
  //         v(0.5em)
  //         index += 1
  //         essay_q_number += 1
  //       }
  //     }
  //   }
  // }
  //
  if mode == "teacher" {
    let question_bank_last_term = none
    heading(level: 2)[EXAM QUESTIONS BANK]

    // Get unique terms in order
    let terms = ()
    for lesson in lessons {
      if not terms.contains(lesson.term) {
        terms.push(lesson.term)
      }
    }

    // Process each term
    for term in terms {
      // Term heading
      heading(level: 3)[#term TERM]

      // Revision Questions section for this term
      heading(level: 4)[REVISION QUESTIONS (Multiple Choice)]
      let objective_q_number = 1

      for lesson in lessons {
        if lesson.term == term {
          if mode == "teacher" {
            if lesson.mcq_questions.len() > 0 {
              let index = 0
              for q in lesson.mcq_questions {
                if index < 5 {
                  index += 1
                  continue
                }
                [#objective_q_number. #q.question ]
                [(a) #q.option_a (b) #q.option_b (c) #q.option_c]
                text(fill: blue, weight: "bold")[ [Ans: #q.correct_answer] \ Explanation: #q.explanation]
                v(0.5em)
                index += 1
                objective_q_number += 1
              }
            }
          }
        }
      }

      // Theoretical Questions section for this term
      heading(level: 4)[THEORETICAL QUESTIONS]
      let essay_q_number = 1

      for lesson in lessons {
        if lesson.term == term {
          if mode == "teacher" {
            if lesson.theoretical_questions.len() > 0 {
              let index = 0
              for q in lesson.theoretical_questions {
                if index < 5 {
                  index += 1
                  continue
                }
                if index >= 6 {
                  break
                }
                [#essay_q_number. #q.question \ ]
                for part in q.parts {
                  [#part ]
                  linebreak()
                }
                text(fill: blue, weight: "bold")[ Ans:\  #q.model_answer]
                v(0.5em)
                index += 1
                essay_q_number += 1
              }
            }
          }
        }
      }
    }
  }
}

// --- EXECUTE ---
#project(
  subject: subject_name,
  year: class_year,
  mode: mode,
  lessons: dummy_lessons,
  header_image: none,
  watermark_image: watermark_image,
)
