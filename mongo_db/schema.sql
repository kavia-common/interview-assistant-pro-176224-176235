-- Interview Assistant Pro - MySQL Schema
-- Database: myapp
-- Purpose: Define core tables and relations for users, interview sessions, questions, responses, feedback, and reports.
--
-- How to apply (assuming MySQL already running via startup.sh and port 5000):
--   mysql -h localhost -P 5000 -u appuser -pdbuser123 myapp < schema.sql
--   mysql -h localhost -P 5000 -u appuser -pdbuser123 myapp < seed.sql
--
-- Note: Keep DB port 5000 to match existing scripts.

-- Use database (created by startup.sh)
CREATE DATABASE IF NOT EXISTS myapp;
USE myapp;

-- Users: Registered users who take interviews (and potentially admin/interviewer roles)
CREATE TABLE IF NOT EXISTS users (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  email         VARCHAR(255) NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  full_name     VARCHAR(255) NOT NULL,
  role          ENUM('candidate', 'admin', 'interviewer') NOT NULL DEFAULT 'candidate',
  is_active     TINYINT(1) NOT NULL DEFAULT 1,
  created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_users_email (email),
  KEY idx_users_role (role),
  KEY idx_users_active (is_active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Questions: Pool of HR and Technical questions with tags and keyword metadata (JSON text)
CREATE TABLE IF NOT EXISTS questions (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  category      ENUM('hr', 'technical') NOT NULL,
  difficulty    ENUM('easy', 'medium', 'hard') NOT NULL DEFAULT 'medium',
  text          TEXT NOT NULL,
  tags          VARCHAR(512) DEFAULT NULL, -- comma-separated tags for quick filter
  keyword_meta  JSON NULL,                 -- JSON text with keywords, e.g., {"keywords":["teamwork","conflict"]}
  created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_questions_category (category),
  KEY idx_questions_difficulty (difficulty),
  FULLTEXT KEY ft_questions_text (text)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Interview Sessions: A session per interview attempt for a user
CREATE TABLE IF NOT EXISTS interview_sessions (
  id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id         BIGINT UNSIGNED NOT NULL,
  title           VARCHAR(255) DEFAULT NULL, -- optional name of the session
  mode            ENUM('text', 'voice') NOT NULL DEFAULT 'text',
  status          ENUM('in_progress', 'completed', 'cancelled') NOT NULL DEFAULT 'in_progress',
  started_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  completed_at    TIMESTAMP NULL DEFAULT NULL,
  overall_score   DECIMAL(5,2) DEFAULT NULL, -- computed at the end
  PRIMARY KEY (id),
  KEY idx_sessions_user (user_id),
  KEY idx_sessions_status (status),
  CONSTRAINT fk_sessions_user
    FOREIGN KEY (user_id) REFERENCES users(id)
    ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Session Questions: which questions are asked in a session, with ordering
CREATE TABLE IF NOT EXISTS session_questions (
  id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  session_id       BIGINT UNSIGNED NOT NULL,
  question_id      BIGINT UNSIGNED NOT NULL,
  position         INT NOT NULL, -- order in session
  asked_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_session_question (session_id, question_id),
  KEY idx_session_questions_session (session_id),
  KEY idx_session_questions_question (question_id),
  CONSTRAINT fk_session_questions_session
    FOREIGN KEY (session_id) REFERENCES interview_sessions(id)
    ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT fk_session_questions_question
    FOREIGN KEY (question_id) REFERENCES questions(id)
    ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Responses: a user's answer to a session question, with automatic scoring and NLP metrics
CREATE TABLE IF NOT EXISTS responses (
  id                 BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  session_question_id BIGINT UNSIGNED NOT NULL,
  response_text      MEDIUMTEXT NULL,
  response_audio_url VARCHAR(1024) DEFAULT NULL, -- if voice mode, link to audio
  sentiment_score    DECIMAL(5,2) DEFAULT NULL,
  relevance_score    DECIMAL(5,2) DEFAULT NULL,
  fluency_score      DECIMAL(5,2) DEFAULT NULL,
  completeness_score DECIMAL(5,2) DEFAULT NULL,
  overall_score      DECIMAL(5,2) DEFAULT NULL,
  created_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_response_per_sq (session_question_id),
  KEY idx_responses_scores (overall_score),
  CONSTRAINT fk_responses_sq
    FOREIGN KEY (session_question_id) REFERENCES session_questions(id)
    ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Feedback: AI-generated feedback for a response and/or entire session
CREATE TABLE IF NOT EXISTS feedback (
  id                 BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  session_id         BIGINT UNSIGNED NOT NULL,
  response_id        BIGINT UNSIGNED DEFAULT NULL, -- null means general session feedback
  feedback_text      MEDIUMTEXT NOT NULL,
  suggestions        MEDIUMTEXT DEFAULT NULL,
  created_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_feedback_session (session_id),
  KEY idx_feedback_response (response_id),
  CONSTRAINT fk_feedback_session
    FOREIGN KEY (session_id) REFERENCES interview_sessions(id)
    ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT fk_feedback_response
    FOREIGN KEY (response_id) REFERENCES responses(id)
    ON UPDATE CASCADE ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Reports: Summarized results and export references after a session
CREATE TABLE IF NOT EXISTS reports (
  id                 BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  session_id         BIGINT UNSIGNED NOT NULL,
  summary            MEDIUMTEXT NOT NULL,
  strengths          MEDIUMTEXT DEFAULT NULL,
  improvements       MEDIUMTEXT DEFAULT NULL,
  export_url         VARCHAR(1024) DEFAULT NULL, -- URL to PDF/HTML export if generated
  created_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_report_session (session_id),
  CONSTRAINT fk_reports_session
    FOREIGN KEY (session_id) REFERENCES interview_sessions(id)
    ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Additional helpful indexes
CREATE INDEX idx_session_time ON interview_sessions (started_at, completed_at);
CREATE INDEX idx_questions_tags ON questions (tags);

-- Views (optional): quick access to response+question
-- Note: MySQL views require sufficient privileges; safe to ignore if insufficient.
DROP VIEW IF EXISTS v_session_answers;
CREATE VIEW v_session_answers AS
SELECT
  sq.session_id,
  q.category,
  q.difficulty,
  q.text AS question_text,
  r.response_text,
  r.overall_score,
  r.created_at AS answered_at
FROM session_questions sq
JOIN questions q ON q.id = sq.question_id
LEFT JOIN responses r ON r.session_question_id = sq.id;

-- Done
