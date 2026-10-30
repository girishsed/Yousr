-- =====================================================================================
-- A Krama stage names its context: the domain profile it works in (a topic or question can name
-- a different one) and, per seat, the person persona needed (areas of expertise and skills).
-- The entity context is the task's own entity. A mismatch is flagged, never blocked.
-- =====================================================================================
ALTER TABLE stage    ADD COLUMN domain_id uuid REFERENCES catalogue_domain(domain_id);
ALTER TABLE topic    ADD COLUMN domain_id uuid REFERENCES catalogue_domain(domain_id);
ALTER TABLE question ADD COLUMN domain_id uuid REFERENCES catalogue_domain(domain_id);

CREATE TABLE seat_need (
  stage_id      uuid NOT NULL REFERENCES stage(stage_id) ON DELETE CASCADE,
  seat          text NOT NULL CHECK (seat IN ('Doer','Reviewer','Approver','SPOC')),
  expertise_ids uuid[] NOT NULL DEFAULT '{}',
  skills        text[] NOT NULL DEFAULT '{}',
  PRIMARY KEY (stage_id, seat)
);
-- A Published Krama is frozen: its seat needs change only through New version
CREATE FUNCTION seat_need_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE k uuid;
BEGIN
  SELECT krama_id INTO k FROM stage WHERE stage_id = CASE WHEN TG_OP = 'DELETE' THEN OLD.stage_id ELSE NEW.stage_id END;
  IF (SELECT status FROM krama WHERE krama_id = k) = 'Published' AND current_setting('demo.seeding', true) IS DISTINCT FROM 'on' THEN
    RAISE EXCEPTION 'This Krama is Published and frozen; create a new version to change it';
  END IF;
  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END $$;
CREATE TRIGGER seat_need_guard BEFORE INSERT OR UPDATE OR DELETE ON seat_need FOR EACH ROW EXECUTE FUNCTION seat_need_guard();

-- New version and Import carry the context across (matched by order)
CREATE FUNCTION copy_stage_context(src uuid, dst uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('demo.seeding', 'on', true);
  UPDATE stage d SET domain_id = s.domain_id FROM stage s WHERE s.krama_id = src AND d.krama_id = dst AND d.seq = s.seq;
  UPDATE topic dt SET domain_id = st.domain_id
    FROM topic st JOIN stage ss ON ss.stage_id = st.stage_id, stage ds
   WHERE ss.krama_id = src AND ds.krama_id = dst AND ds.seq = ss.seq AND dt.stage_id = ds.stage_id AND dt.seq = st.seq;
  UPDATE question dq SET domain_id = sq.domain_id
    FROM question sq JOIN topic st ON st.topic_id = sq.topic_id JOIN stage ss ON ss.stage_id = st.stage_id, topic dt JOIN stage ds ON ds.stage_id = dt.stage_id
   WHERE ss.krama_id = src AND ds.krama_id = dst AND ds.seq = ss.seq AND dt.seq = st.seq AND dq.topic_id = dt.topic_id AND dq.seq = sq.seq;
  INSERT INTO seat_need (stage_id, seat, expertise_ids, skills)
  SELECT ds.stage_id, n.seat, n.expertise_ids, n.skills FROM seat_need n JOIN stage ss ON ss.stage_id = n.stage_id JOIN stage ds ON ds.krama_id = dst AND ds.seq = ss.seq
   WHERE ss.krama_id = src;
  PERFORM set_config('demo.seeding', 'off', true);
END $$;

-- ---------- design side (Krama console) ----------
CREATE FUNCTION api_krama_context(actor uuid, b jsonb) RETURNS json LANGUAGE sql STABLE AS $$
  SELECT json_build_object(
    'domains', (SELECT COALESCE(json_agg(json_build_object('domain_id', d.domain_id, 'name', d.catalogue || ' › ' || d.name) ORDER BY d.catalogue, d.name), '[]') FROM catalogue_domain d),
    'expertise', (SELECT COALESCE(json_agg(json_build_object('expertise_id', x.expertise_id, 'name', x.name) ORDER BY x.name), '[]') FROM expertise x),
    'stages', (SELECT COALESCE(json_object_agg(s.stage_id, json_build_object('domain_id', s.domain_id,
                 'needs', (SELECT COALESCE(json_object_agg(n.seat, json_build_object('expertise_ids', n.expertise_ids, 'skills', n.skills)), '{}') FROM seat_need n WHERE n.stage_id = s.stage_id))), '{}')
               FROM stage s WHERE s.krama_id = (b->>'krama_id')::uuid),
    'topics', (SELECT COALESCE(json_object_agg(t.topic_id, t.domain_id), '{}') FROM topic t JOIN stage s USING (stage_id) WHERE s.krama_id = (b->>'krama_id')::uuid),
    'questions', (SELECT COALESCE(json_object_agg(q.question_id, q.domain_id), '{}') FROM question q JOIN topic t USING (topic_id) JOIN stage s USING (stage_id) WHERE s.krama_id = (b->>'krama_id')::uuid))
$$;

CREATE FUNCTION api_set_context(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
DECLARE k uuid; id uuid := (b->>'id')::uuid; d uuid := NULLIF(b->>'domain_id', '')::uuid;
BEGIN
  k := CASE j(b, 'level') WHEN 'stage' THEN krama_of('stage', id) WHEN 'topic' THEN krama_of('topic', id) WHEN 'question' THEN krama_of('question', id) END;
  IF k IS NULL THEN RAISE EXCEPTION 'Pick a stage, topic or question'; END IF;
  IF NOT can_design(actor, k) THEN RAISE EXCEPTION 'You cannot change this Krama'; END IF;
  IF j(b, 'level') = 'stage' THEN UPDATE stage SET domain_id = d WHERE stage_id = id;
  ELSIF j(b, 'level') = 'topic' THEN UPDATE topic SET domain_id = d WHERE topic_id = id;
  ELSE UPDATE question SET domain_id = d WHERE question_id = id; END IF;
  RETURN json_build_object('ok', true);
END $$;

CREATE FUNCTION api_set_seat_need(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
DECLARE st uuid := (b->>'stage_id')::uuid;
BEGIN
  IF NOT can_design(actor, krama_of('stage', st)) THEN RAISE EXCEPTION 'You cannot change this Krama'; END IF;
  IF jsonb_array_length(COALESCE(b->'expertise_ids', '[]')) = 0 AND COALESCE(j(b, 'skills'), '') = '' THEN
    DELETE FROM seat_need WHERE stage_id = st AND seat = j(b, 'seat');
  ELSE
    INSERT INTO seat_need (stage_id, seat, expertise_ids, skills)
    VALUES (st, j(b, 'seat'), ARRAY(SELECT jsonb_array_elements_text(COALESCE(b->'expertise_ids', '[]'))::uuid), lines(b->>'skills'))
    ON CONFLICT (stage_id, seat) DO UPDATE SET expertise_ids = EXCLUDED.expertise_ids, skills = EXCLUDED.skills;
  END IF;
  RETURN json_build_object('ok', true);
END $$;

-- ---------- run side ----------
-- How well a person fits a seat's need: which expertise and skills match, and what is missing
CREATE FUNCTION person_fit(p uuid, n seat_need) RETURNS json LANGUAGE sql STABLE AS $$
  SELECT json_build_object(
    'matches', (cardinality(n.expertise_ids) = 0 OR (SELECT u.expertise_ids && n.expertise_ids FROM users u WHERE u.user_id = p))
           AND (cardinality(n.skills) = 0 OR EXISTS (SELECT 1 FROM person_persona pp WHERE pp.person_id = p
                  AND EXISTS (SELECT 1 FROM unnest(pp.skills) s, unnest(n.skills) k WHERE lower(s) = lower(k)))),
    'matched', (SELECT COALESCE(json_agg(x.name), '[]') FROM expertise x WHERE x.expertise_id = ANY (n.expertise_ids)
                   AND x.expertise_id = ANY ((SELECT expertise_ids FROM users WHERE user_id = p)::uuid[]))
           ::jsonb || (SELECT COALESCE(json_agg(k), '[]') FROM unnest(n.skills) k WHERE EXISTS (SELECT 1 FROM person_persona pp, unnest(pp.skills) s WHERE pp.person_id = p AND lower(s) = lower(k)))::jsonb)
$$;

CREATE FUNCTION domain_brief(d uuid) RETURNS json LANGUAGE sql STABLE AS $$
  SELECT json_build_object('domain_id', cd.domain_id, 'name', cd.catalogue || ' › ' || cd.name, 'objectives', dp.objectives,
           'regulations', dp.regulations, 'controls', dp.controls, 'compliance_requirements', dp.compliance_requirements)
    FROM catalogue_domain cd LEFT JOIN domain_profile dp USING (domain_id) WHERE cd.domain_id = d
$$;

-- The task's context: whose work it is (Entity Profile), each stage's domain profile and persona needs,
-- topic and question overrides, and each seated person's fit
CREATE FUNCTION api_task_context(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql STABLE AS $$
DECLARE r run;
BEGIN
  SELECT * INTO r FROM run WHERE run_id = (b->>'run_id')::uuid;
  IF r IS NULL OR r.run_id NOT IN (SELECT visible_runs(actor)) THEN RAISE EXCEPTION 'Task not found'; END IF;
  RETURN json_build_object(
    'entity', (SELECT entity_brief(r.company_user_id)),
    'stages', (SELECT COALESCE(json_agg(json_build_object('stage_id', s.stage_id, 'name', s.name, 'domain', domain_brief(s.domain_id),
                 'needs', (SELECT COALESCE(json_agg(json_build_object('seat', n.seat,
                              'expertise', (SELECT COALESCE(json_agg(x.name), '[]') FROM expertise x WHERE x.expertise_id = ANY (n.expertise_ids)), 'skills', n.skills)), '[]')
                           FROM seat_need n WHERE n.stage_id = s.stage_id),
                 'topics', (SELECT COALESCE(json_agg(json_build_object('topic_id', t.topic_id, 'name', t.name, 'domain', domain_brief(t.domain_id))), '[]')
                            FROM topic t WHERE t.stage_id = s.stage_id AND t.domain_id IS NOT NULL AND t.domain_id IS DISTINCT FROM s.domain_id),
                 'questions', (SELECT COALESCE(json_agg(json_build_object('question_id', q.question_id, 'text', q.text, 'domain', domain_brief(q.domain_id))), '[]')
                            FROM question q JOIN topic t USING (topic_id) WHERE t.stage_id = s.stage_id AND q.domain_id IS NOT NULL
                              AND q.domain_id IS DISTINCT FROM COALESCE(t.domain_id, s.domain_id))) ORDER BY s.seq), '[]')
               FROM stage s WHERE s.krama_id = r.krama_id),
    'seats', (SELECT COALESCE(json_agg(json_build_object('seat_id', se.seat_id, 'fit', person_fit(se.person_id, n))), '[]')
                FROM seat se JOIN seat_need n ON n.stage_id = se.stage_id AND n.seat = se.seat WHERE se.run_id = r.run_id),
    'candidates', (SELECT COALESCE(json_agg(json_build_object('stage_id', n.stage_id, 'seat', n.seat, 'person_id', l.person_id, 'name', user_name(l.person_id), 'fit', person_fit(l.person_id, n))), '[]')
                     FROM seat_need n JOIN stage s ON s.stage_id = n.stage_id AND s.krama_id = r.krama_id
                     JOIN person_entity_link l ON l.company_user_id IN (r.company_user_id, r.counterparty)));
END $$;

-- ---------- sample context on the sample Kramas ----------
SELECT set_config('demo.seeding', 'on', false);
UPDATE stage s SET domain_id = 'd0000000-0000-0000-0000-000000000004' FROM krama k
 WHERE k.krama_id = s.krama_id AND k.name ILIKE '%expense%';
UPDATE stage s SET domain_id = 'd0000000-0000-0000-0000-000000000005' FROM krama k
 WHERE k.krama_id = s.krama_id AND k.name ILIKE '%vendor invoice%';
INSERT INTO seat_need (stage_id, seat, expertise_ids, skills)
SELECT s.stage_id, 'Approver', '{e0000000-0000-0000-0000-000000000001}', '{}' FROM stage s JOIN krama k USING (krama_id)
 WHERE k.name ILIKE '%expense%' AND s.name ILIKE '%approve%'
ON CONFLICT DO NOTHING;
INSERT INTO seat_need (stage_id, seat, expertise_ids, skills)
SELECT s.stage_id, 'Doer', '{e0000000-0000-0000-0000-000000000004}', '{}' FROM stage s JOIN krama k USING (krama_id)
 WHERE k.name ILIKE '%vendor invoice%' AND s.seq = 1
ON CONFLICT DO NOTHING;
SELECT set_config('demo.seeding', 'off', false);

-- Sample profiles so the context shows something in the sample tasks
INSERT INTO domain_profile (domain_id, objectives, terminology, regulations, typical_workflows, controls, compliance_requirements) VALUES
 ('d0000000-0000-0000-0000-000000000004', 'Pay employees and vendors correctly, with evidence.', '{Claim,Receipt,Reimbursement}', '{}', '{Submit,Review,Approve,Pay}', '{Receipts for every claim,Maker-checker on payment}', NULL),
 ('d0000000-0000-0000-0000-000000000005', 'Buy from approved vendors at agreed terms.', '{Purchase order,Delivery note,Invoice}', '{}', '{Order,Receive,Match,Pay}', '{Three-way match before payment}', NULL)
ON CONFLICT (domain_id) DO NOTHING;
UPDATE company SET objectives = 'Grow retail sales across two stores.', capabilities = '{Store operations,Buying,Finance}'
 WHERE user_id = '11111111-0000-0000-0000-000000000012';
