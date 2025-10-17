-- Interview Assistant Pro - Seed Data
-- Apply after schema.sql:
--   mysql -h localhost -P 5000 -u appuser -pdbuser123 myapp < seed.sql

USE myapp;

-- Users
INSERT INTO users (email, password_hash, full_name, role, is_active)
VALUES
  ('alice@example.com', '$2b$10$examplehashAlice', 'Alice Johnson', 'candidate', 1),
  ('bob@example.com', '$2b$10$examplehashBob', 'Bob Smith', 'candidate', 1),
  ('admin@example.com', '$2b$10$examplehashAdmin', 'Admin User', 'admin', 1)
ON DUPLICATE KEY UPDATE email = VALUES(email);

-- Questions: HR
INSERT INTO questions (category, difficulty, text, tags, keyword_meta)
VALUES
  (
    'hr', 'easy',
    'Tell me about yourself.',
    'hr,introduction,behavioral',
    JSON_OBJECT('keywords', JSON_ARRAY('background','experience','summary','strengths'))
  ),
  (
    'hr', 'medium',
    'Describe a challenging situation at work and how you handled it.',
    'hr,behavioral,challenge,problem-solving',
    JSON_OBJECT('keywords', JSON_ARRAY('challenge','conflict','resolution','impact'))
  ),
  (
    'hr', 'medium',
    'What motivates you in your professional life?',
    'hr,motivation,culture',
    JSON_OBJECT('keywords', JSON_ARRAY('motivation','values','drive','goals'))
  )
ON DUPLICATE KEY UPDATE updated_at = CURRENT_TIMESTAMP;

-- Questions: Technical
INSERT INTO questions (category, difficulty, text, tags, keyword_meta)
VALUES
  (
    'technical', 'easy',
    'What is the time complexity of binary search?',
    'technical,algorithms,big-o',
    JSON_OBJECT('keywords', JSON_ARRAY('O(log n)','divide and conquer','sorted array'))
  ),
  (
    'technical', 'medium',
    'Explain the difference between SQL JOIN types (INNER, LEFT, RIGHT, FULL).',
    'technical,databases,sql',
    JSON_OBJECT('keywords', JSON_ARRAY('join','inner','left','right','full','relational'))
  ),
  (
    'technical', 'hard',
    'How does a RESTful API differ from GraphQL and when would you choose one over the other?',
    'technical,api,architecture',
    JSON_OBJECT('keywords', JSON_ARRAY('REST','GraphQL','trade-offs','over-fetching','under-fetching'))
  )
ON DUPLICATE KEY UPDATE updated_at = CURRENT_TIMESTAMP;

-- Example session for Alice
-- Create a session
INSERT INTO interview_sessions (user_id, title, mode, status)
SELECT id, 'Practice Session 1', 'text', 'in_progress'
FROM users WHERE email = 'alice@example.com'
LIMIT 1;

-- Link two questions to the session
-- Use the latest session id for Alice
SET @session_id = (
  SELECT s.id
  FROM interview_sessions s
  JOIN users u ON u.id = s.user_id
  WHERE u.email = 'alice@example.com'
  ORDER BY s.started_at DESC, s.id DESC
  LIMIT 1
);

-- Choose two questions (one HR, one Technical)
SET @q_hr = (SELECT id FROM questions WHERE category='hr' ORDER BY id ASC LIMIT 1);
SET @q_tech = (SELECT id FROM questions WHERE category='technical' ORDER BY id ASC LIMIT 1);

INSERT INTO session_questions (session_id, question_id, position)
VALUES
  (@session_id, @q_hr, 1),
  (@session_id, @q_tech, 2);

-- Add example responses with simple scores
SET @sq1 = (SELECT id FROM session_questions WHERE session_id=@session_id AND question_id=@q_hr);
SET @sq2 = (SELECT id FROM session_questions WHERE session_id=@session_id AND question_id=@q_tech);

INSERT INTO responses (session_question_id, response_text, sentiment_score, relevance_score, fluency_score, completeness_score, overall_score)
VALUES
  (@sq1, 'I have a background in software engineering with a focus on building scalable web applications.', 0.80, 0.85, 0.88, 0.82, 0.84),
  (@sq2, 'Binary search runs in O(log n) time by repeatedly dividing the search interval in half.', 0.78, 0.92, 0.86, 0.90, 0.87);

-- Add feedback for each response
INSERT INTO feedback (session_id, response_id, feedback_text, suggestions)
VALUES
  (@session_id, (SELECT id FROM responses WHERE session_question_id=@sq1),
   'Clear and concise summary. Consider adding a specific project highlight.', 'Include metrics and outcomes from a key project.'),
  (@session_id, (SELECT id FROM responses WHERE session_question_id=@sq2),
   'Accurate and well-explained.', 'Mention prerequisites such as the array being sorted for completeness.');

-- Finalize session summary report (example)
INSERT INTO reports (session_id, summary, strengths, improvements, export_url)
VALUES
  (@session_id,
   'Strong foundational knowledge and good communication. Focus on adding measurable impact to examples.',
   'Communication clarity; Core CS understanding.',
   'Provide more detailed examples with metrics.',
   NULL);

-- Optionally mark session as completed and set an overall score
UPDATE interview_sessions
SET status='completed',
    completed_at = CURRENT_TIMESTAMP,
    overall_score = (
      SELECT ROUND(AVG(overall_score), 2) FROM responses r
      JOIN session_questions sq ON sq.id = r.session_question_id
      WHERE sq.session_id = interview_sessions.id
    )
WHERE id=@session_id;
