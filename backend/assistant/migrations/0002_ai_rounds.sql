-- One row per AI model call: numbers only, never what was said or shown. For checking that the AI
-- editor sees pictures, how many rounds it takes, and what it costs.
CREATE TABLE IF NOT EXISTS ai_rounds (
  at INTEGER NOT NULL,
  kind TEXT NOT NULL,
  model TEXT NOT NULL DEFAULT '',
  ok INTEGER NOT NULL,
  status INTEGER NOT NULL DEFAULT 200,
  input_tokens INTEGER NOT NULL DEFAULT 0,
  cached_tokens INTEGER NOT NULL DEFAULT 0,
  output_tokens INTEGER NOT NULL DEFAULT 0,
  pictures INTEGER NOT NULL DEFAULT 0,
  pictures_refused INTEGER NOT NULL DEFAULT 0,
  calls TEXT NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS ai_rounds_at ON ai_rounds(at);
