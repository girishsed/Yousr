-- =====================================================================================
-- Feedback: what people say should be different, given under any answer in the chat.
-- Reviewed by the platform super-user under Masters › Feedback (Open → Done).
-- =====================================================================================
CREATE TABLE IF NOT EXISTS feedback (
  feedback_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  person_id   uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  entity_id   uuid REFERENCES users(user_id) ON DELETE SET NULL,
  asked       text,
  answer      text,
  text        text NOT NULL,
  status      text NOT NULL DEFAULT 'Open' CHECK (status IN ('Open','Done')),
  given_at    timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE OR REPLACE FUNCTION api_give_feedback(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
DECLARE e uuid := NULLIF(b->>'entity_id', '')::uuid; tx text := btrim(b->>'text');
BEGIN
  IF actor IS NULL THEN RAISE EXCEPTION 'Sign in first'; END IF;
  IF tx IS NULL OR tx = '' THEN RAISE EXCEPTION 'Type or say your feedback first'; END IF;
  IF length(tx) > 2000 THEN RAISE EXCEPTION 'Please keep feedback under 2000 characters'; END IF;
  IF e IS NOT NULL AND NOT is_member_of_entity(actor, e) THEN e := NULL; END IF;
  INSERT INTO feedback (person_id, entity_id, asked, answer, text)
       VALUES (actor, e, left(b->>'asked', 500), left(b->>'answer', 500), tx);
  RETURN json_build_object('saved', true);
END $$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    ALTER TABLE public.feedback ENABLE ROW LEVEL SECURITY;
    REVOKE ALL ON public.feedback FROM anon, authenticated;
    REVOKE EXECUTE ON FUNCTION api_give_feedback(uuid, jsonb) FROM anon, authenticated, public;
  END IF;
END $$;
