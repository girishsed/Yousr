-- =====================================================================================
-- How often a wording has worked for a person with no correction. After 3 such uses the chat
-- stops showing "Not what I meant / Teach this / Give feedback" under its answer.
-- Any correction (Not what I meant, Teach this, None of these, Give feedback) sets the count back to 0.
-- =====================================================================================
CREATE TABLE IF NOT EXISTS phrase_use (
  person_id uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  phrase    text NOT NULL,
  uses      int  NOT NULL DEFAULT 0,
  PRIMARY KEY (person_id, phrase)
);

CREATE OR REPLACE FUNCTION api_note_use(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
DECLARE ph text := lower(btrim(b->>'phrase')); rs boolean := COALESCE((b->>'reset')::boolean, false); n int;
BEGIN
  IF actor IS NULL THEN RAISE EXCEPTION 'Sign in first'; END IF;
  IF ph IS NULL OR ph = '' OR length(ph) > 200 THEN RETURN json_build_object('uses', 0); END IF;
  INSERT INTO phrase_use (person_id, phrase, uses) VALUES (actor, ph, CASE WHEN rs THEN 0 ELSE 1 END)
    ON CONFLICT (person_id, phrase) DO UPDATE SET uses = CASE WHEN rs THEN 0 ELSE phrase_use.uses + 1 END
    RETURNING uses INTO n;
  RETURN json_build_object('uses', n);
END $$;

CREATE OR REPLACE FUNCTION api_my_uses(actor uuid, b jsonb) RETURNS json LANGUAGE sql STABLE AS $$
  SELECT COALESCE(json_object_agg(phrase, uses), '{}') FROM phrase_use WHERE person_id = actor
$$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    ALTER TABLE public.phrase_use ENABLE ROW LEVEL SECURITY;
    REVOKE ALL ON public.phrase_use FROM anon, authenticated;
    REVOKE EXECUTE ON FUNCTION api_note_use(uuid, jsonb), api_my_uses(uuid, jsonb) FROM anon, authenticated, public;
  END IF;
END $$;
