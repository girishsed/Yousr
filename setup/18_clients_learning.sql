-- =====================================================================================
-- Clients and vendors of an entity in one plain list, whatever their kind:
-- a task run with them, an accepted connection, or a standalone listing (not on the platform).
-- Pending invites and expired or cancelled ones do not count.
-- =====================================================================================
CREATE OR REPLACE FUNCTION api_counterparties(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql STABLE AS $$
DECLARE
  e    uuid := NULLIF(b->>'entity_id', '')::uuid;
  mine text[] := CASE WHEN b->>'side' = 'vendors' THEN ARRAY['Pre-vendor','Vendor'] ELSE ARRAY['Pre-client','Client'] END;
  them text[] := CASE WHEN b->>'side' = 'vendors' THEN ARRAY['Pre-client','Client'] ELSE ARRAY['Pre-vendor','Vendor'] END;
BEGIN
  IF e IS NULL OR actor IS NULL OR NOT is_member_of_entity(actor, e) THEN RAISE EXCEPTION 'You are not a member of this entity'; END IF;
  RETURN (
    WITH p AS (
      SELECT counterparty AS uid, NULL::text AS nm FROM run WHERE company_user_id = e AND counterparty IS NOT NULL AND relationship = ANY (mine)
      UNION SELECT company_user_id, NULL FROM run WHERE counterparty = e AND relationship = ANY (them)
      UNION SELECT to_entity, to_name FROM entity_connection
             WHERE from_entity = e AND relationship = ANY (mine) AND state IN ('Standalone','Connected') AND failure IS NULL
      UNION SELECT from_entity, NULL FROM entity_connection
             WHERE to_entity = e AND relationship = ANY (them) AND state = 'Connected' AND failure IS NULL
    ), d AS (
      SELECT DISTINCT ON (COALESCE(uid::text, lower(nm))) uid, COALESCE(user_name(uid), nm) AS name
        FROM p WHERE (uid IS NULL OR uid <> e) AND COALESCE(user_name(uid), nm) IS NOT NULL
       ORDER BY COALESCE(uid::text, lower(nm)), uid NULLS LAST
    )
    SELECT COALESCE(json_agg(json_build_object('entity_id', d.uid, 'name', d.name,
             'persona', (SELECT pt.display_name FROM company c JOIN persona_type pt USING (persona_type_id) WHERE c.user_id = d.uid),
             'open', (SELECT count(*) FROM run r WHERE r.locked_at IS NULL AND d.uid IS NOT NULL
                       AND ((r.company_user_id = e AND r.counterparty = d.uid) OR (r.company_user_id = d.uid AND r.counterparty = e))))
           ORDER BY d.name), '[]') FROM d);
END $$;

-- =====================================================================================
-- Learning, per person: when a request isn't understood and the person taps a suggestion,
-- the platform remembers what that wording means for them and goes straight there next time.
-- =====================================================================================
CREATE TABLE IF NOT EXISTS learned_phrase (
  person_id  uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  phrase     text NOT NULL,
  means      text NOT NULL,
  learned_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (person_id, phrase)
);

CREATE OR REPLACE FUNCTION api_learn_phrase(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
DECLARE ph text := lower(btrim(b->>'phrase')); mn text := btrim(b->>'means');
BEGIN
  IF actor IS NULL THEN RAISE EXCEPTION 'Sign in first'; END IF;
  IF ph IS NULL OR ph = '' OR mn IS NULL OR mn = '' OR length(ph) > 200 OR length(mn) > 200 THEN RAISE EXCEPTION 'Nothing to learn'; END IF;
  INSERT INTO learned_phrase (person_id, phrase, means) VALUES (actor, ph, mn)
    ON CONFLICT (person_id, phrase) DO UPDATE SET means = EXCLUDED.means, learned_at = clock_timestamp();
  RETURN json_build_object('learned', true);
END $$;

CREATE OR REPLACE FUNCTION api_my_phrases(actor uuid, b jsonb) RETURNS json LANGUAGE sql STABLE AS $$
  SELECT COALESCE(json_object_agg(phrase, means), '{}') FROM learned_phrase WHERE person_id = actor
$$;

CREATE OR REPLACE FUNCTION api_forget_phrase(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
BEGIN
  IF actor IS NULL THEN RAISE EXCEPTION 'Sign in first'; END IF;
  DELETE FROM learned_phrase WHERE person_id = actor AND phrase = lower(btrim(b->>'phrase'));
  RETURN json_build_object('forgotten', true);
END $$;

-- On Supabase: keep the new table behind the API, like every other table
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    ALTER TABLE public.learned_phrase ENABLE ROW LEVEL SECURITY;
    REVOKE ALL ON public.learned_phrase FROM anon, authenticated;
    REVOKE EXECUTE ON FUNCTION api_counterparties(uuid, jsonb), api_learn_phrase(uuid, jsonb), api_my_phrases(uuid, jsonb), api_forget_phrase(uuid, jsonb) FROM anon, authenticated, public;
  END IF;
END $$;
