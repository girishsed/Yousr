-- =====================================================================================
-- Personas: Work Persona decides what a person sees and may do; Entity Persona carries applicability
-- and its obligatory / non-obligatory forks; Domain persona is defined (not just a name); Human Persona
-- resolves Kramas for a person counterparty; and the authority spine: seats come from the legal form,
-- and a persona attaches to an existing seat, never creates one.
-- =====================================================================================

-- ---------- Work Persona: modules and actions ----------
ALTER TABLE work_persona ADD COLUMN actions text[] NOT NULL DEFAULT '{View}';
CREATE FUNCTION all_modules() RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
  SELECT ARRAY['WOM','Krama','Catalogue','Vendors','Connections','Revenue','Compliance','Reports']
$$;

-- What a person may see and do in an entity: an entity admin has everything; otherwise their Work Persona;
-- with no Work Persona yet, only the default WOM and View
CREATE FUNCTION person_access(p uuid, e uuid) RETURNS json LANGUAGE sql STABLE AS $$
  SELECT CASE
    WHEN is_super(p) OR is_entity_super(p, e) THEN json_build_object('admin', true, 'modules', all_modules(), 'actions', ARRAY['View','Approve','Sign'], 'persona', 'Entity admin')
    WHEN wp.persona_id IS NOT NULL THEN json_build_object('admin', false, 'modules', wp.modules, 'actions', wp.actions, 'persona', wp.name)
    ELSE json_build_object('admin', false, 'modules', ARRAY['WOM'], 'actions', ARRAY['View'], 'persona', NULL) END
  FROM (SELECT 1) one
  LEFT JOIN person_entity_link l ON l.person_id = p AND l.company_user_id = e
  LEFT JOIN work_persona wp ON wp.persona_id = l.persona_id
$$;

CREATE FUNCTION has_module(p uuid, e uuid, m text) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT m = ANY (SELECT json_array_elements_text(person_access(p, e)->'modules'))
$$;
CREATE FUNCTION has_action(p uuid, e uuid, a text) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT a = ANY (SELECT json_array_elements_text(person_access(p, e)->'actions'))
$$;
CREATE FUNCTION need_module(actor uuid, e uuid, m text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM need_member(actor, e);
  IF NOT has_module(actor, e, m) THEN RAISE EXCEPTION 'Your Work Persona does not include %. Ask your entity admin.', m; END IF;
END $$;

CREATE FUNCTION api_my_access(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql STABLE AS $$
BEGIN
  PERFORM need_member(actor, (b->>'entity_id')::uuid);
  RETURN person_access(actor, (b->>'entity_id')::uuid);
END $$;

-- Work Persona edits: modules, actions and the seat it attaches to
CREATE FUNCTION api_persona_edit(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
DECLARE wp record; m text; a text;
BEGIN
  SELECT * INTO wp FROM work_persona WHERE persona_id = (b->>'persona_id')::uuid;
  IF wp.persona_id IS NULL THEN RAISE EXCEPTION 'Work Persona not found'; END IF;
  PERFORM need_dept_rights(actor, wp.entity_id, wp.dept_bu_id);
  FOR m IN SELECT json_array_elements_text(COALESCE((b->'modules')::json, '[]')) LOOP
    IF NOT m = ANY (all_modules()) THEN RAISE EXCEPTION 'Unknown module %', m; END IF;
  END LOOP;
  FOR a IN SELECT json_array_elements_text(COALESCE((b->'actions')::json, '[]')) LOOP
    IF a NOT IN ('View','Approve','Sign') THEN RAISE EXCEPTION 'Actions are View, Approve and Sign'; END IF;
  END LOOP;
  UPDATE work_persona SET
    modules = CASE WHEN b ? 'modules' THEN ARRAY(SELECT jsonb_array_elements_text(b->'modules')) ELSE modules END,
    actions = CASE WHEN b ? 'actions' THEN ARRAY(SELECT jsonb_array_elements_text(b->'actions')) ELSE actions END,
    seat_id = CASE WHEN b ? 'seat_id' THEN NULLIF(b->>'seat_id', '')::uuid ELSE seat_id END
   WHERE persona_id = wp.persona_id;
  RETURN json_build_object('ok', true);
END $$;

-- Approving needs the Approve action; signing a version needs Sign
CREATE OR REPLACE FUNCTION seat_person(p_run uuid, p_stage uuid, p_seat text, p_person uuid, actor uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE r record; st record; counter boolean;
BEGIN
  SELECT * INTO r FROM run WHERE run_id = p_run;
  IF r IS NULL THEN RAISE EXCEPTION 'Run not found'; END IF;
  IF r.requestor_id <> actor AND NOT is_super(actor) THEN RAISE EXCEPTION 'Only the Requestor/Conductor seats people'; END IF;
  IF r.locked_at IS NOT NULL THEN RAISE EXCEPTION 'This run is conserved; amend it first'; END IF;
  SELECT * INTO st FROM stage WHERE stage_id = p_stage AND krama_id = r.krama_id;
  IF st IS NULL THEN RAISE EXCEPTION 'Stage is not part of this run'; END IF;
  IF user_type_of(p_person) IS DISTINCT FROM 'Individual' THEN RAISE EXCEPTION 'Only a person can take a seat'; END IF;
  counter := r.counterparty IS NOT NULL AND is_member_of_entity(p_person, r.counterparty)
             AND NOT is_member_of_entity(p_person, r.company_user_id);
  IF NOT counter AND NOT is_member_of_entity(p_person, r.company_user_id) THEN
    RAISE EXCEPTION 'The person must belong to this entity or the counterparty';
  END IF;
  IF counter AND path_rank(st.path) < 3 THEN
    RAISE EXCEPTION 'This stage never reaches the external room, so the counterparty cannot be seated in it';
  END IF;
  IF p_seat = 'Approver' AND NOT has_action(p_person, CASE WHEN counter THEN r.counterparty ELSE r.company_user_id END, 'Approve') THEN
    RAISE EXCEPTION '%''s Work Persona does not allow Approve', user_name(p_person);
  END IF;
  INSERT INTO seat (run_id, stage_id, seat, person_id) VALUES (p_run, p_stage, p_seat, p_person) ON CONFLICT DO NOTHING;
  INSERT INTO room_member (room_id, person_id, is_spoc)
  SELECT rm.room_id, p_person, p_seat = 'SPOC' FROM room rm
   WHERE rm.run_id = p_run AND rm.parent_room_id IS NULL
     AND ((counter AND rm.kind = 'ER') OR (NOT counter AND kind_rank(rm.kind) <= path_rank(st.path)))
  ON CONFLICT (room_id, person_id) DO UPDATE SET is_spoc = room_member.is_spoc OR EXCLUDED.is_spoc;
  PERFORM log_run(p_run, actor, 'Seated', user_name(p_person) || ' as ' || p_seat || ' for ' || st.name);
END $$;

CREATE OR REPLACE FUNCTION submit_answer(qr uuid, actor uuid, p_answer text, p_source text, p_data jsonb DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $$
DECLARE c record; q question; side uuid;
BEGIN
  PERFORM assert_can_act(qr, actor, ARRAY['Doer']);
  SELECT * INTO c FROM qr_ctx(qr);
  IF c.answer_state NOT IN ('Pending','Contested') THEN RAISE EXCEPTION 'This question is not waiting for an answer'; END IF;
  IF coalesce(trim(p_answer), '') = '' THEN RAISE EXCEPTION 'Answer is required'; END IF;
  SELECT question.* INTO q FROM question JOIN question_run USING (question_id) WHERE qr_id = qr;
  IF q.flow_option = 'Signature panel' THEN
    SELECT CASE WHEN is_member_of_entity(actor, r.company_user_id) THEN r.company_user_id ELSE r.counterparty END INTO side FROM run r WHERE r.run_id = c.run_id;
    IF NOT has_action(actor, side, 'Sign') THEN RAISE EXCEPTION 'Your Work Persona does not allow Sign'; END IF;
  END IF;
  PERFORM check_answer(q, p_data);
  UPDATE question_run SET answer = p_answer, answer_data = p_data, answer_state = 'Submitted', source = COALESCE(p_source, 'Person') WHERE qr_id = qr;
  INSERT INTO answer_round (qr_id, kind, body, data, by_person) VALUES (qr, 'Submit', p_answer, p_data, actor);
  PERFORM log_run(c.run_id, actor, 'Submitted', p_answer);
END $$;

-- ---------- Authority spine: seats from the legal form; personas attach to them ----------
CREATE TABLE legal_form_seat (
  company_type_id uuid NOT NULL REFERENCES company_type(company_type_id),
  seat            text NOT NULL,
  min_count       integer NOT NULL,
  max_count       integer,                 -- null: no upper limit set by the legal form
  seq             integer NOT NULL,
  PRIMARY KEY (company_type_id, seat)
);
CREATE TABLE entity_seat (
  seat_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_id uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  seat      text NOT NULL,
  min_count integer NOT NULL,
  max_count integer,
  seq       integer NOT NULL,
  UNIQUE (entity_id, seat)
);
ALTER TABLE work_persona ADD COLUMN seat_id uuid REFERENCES entity_seat(seat_id);

-- Seat minimums and maximums set by law for each legal form (India)
INSERT INTO legal_form_seat (company_type_id, seat, min_count, max_count, seq)
SELECT ct.company_type_id, v.seat, v.mn, v.mx, v.seq FROM company_type ct JOIN (VALUES
  ('Sole proprietor', 'Proprietor', 1, 1, 1),
  ('Partnership firm', 'Partners', 2, 50, 1),
  ('Pvt Ltd', 'Shareholders', 2, 200, 1), ('Pvt Ltd', 'Directors', 2, 15, 2),
  ('LLP', 'Designated partners', 2, NULL, 1), ('LLP', 'Partners', 2, NULL, 2),
  ('Public Ltd', 'Shareholders', 7, NULL, 1), ('Public Ltd', 'Directors', 3, 15, 2),
  ('Trust', 'Trustees', 1, NULL, 1)
) v(form, seat, mn, mx, seq) ON v.form = ct.sub_type;

-- The entity instantiates its spine from its legal form
CREATE FUNCTION instantiate_spine(e uuid) RETURNS void LANGUAGE sql AS $$
  INSERT INTO entity_seat (entity_id, seat, min_count, max_count, seq)
  SELECT e, s.seat, s.min_count, s.max_count, s.seq FROM legal_form_seat s JOIN company c ON c.company_type_id = s.company_type_id
   WHERE c.user_id = e
  ON CONFLICT (entity_id, seat) DO NOTHING
$$;
CREATE FUNCTION spine_after_company() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN PERFORM instantiate_spine(NEW.user_id); RETURN NEW; END $$;
CREATE TRIGGER spine_after_company AFTER INSERT ON company FOR EACH ROW EXECUTE FUNCTION spine_after_company();
SELECT instantiate_spine(user_id) FROM company;

-- A seat is filled by the people whose Work Persona attaches to it; a full seat takes nobody more
CREATE FUNCTION seat_fill_check() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE s record; n int;
BEGIN
  IF NEW.persona_id IS NULL OR NEW.persona_id IS NOT DISTINCT FROM OLD.persona_id THEN RETURN NEW; END IF;
  SELECT es.* INTO s FROM work_persona wp JOIN entity_seat es ON es.seat_id = wp.seat_id WHERE wp.persona_id = NEW.persona_id;
  IF s IS NULL OR s.max_count IS NULL THEN RETURN NEW; END IF;
  SELECT count(*) INTO n FROM person_entity_link l JOIN work_persona wp ON wp.persona_id = l.persona_id
   WHERE wp.seat_id = s.seat_id AND l.link_id <> NEW.link_id;
  IF n >= s.max_count THEN RAISE EXCEPTION 'The % seat is full (% of %)', s.seat, n, s.max_count; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER seat_fill_check BEFORE INSERT OR UPDATE OF persona_id ON person_entity_link FOR EACH ROW EXECUTE FUNCTION seat_fill_check();

CREATE FUNCTION api_spine(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql STABLE AS $$
DECLARE e uuid := (b->>'entity_id')::uuid;
BEGIN
  PERFORM need_member(actor, e);
  RETURN (SELECT COALESCE(json_agg(json_build_object('seat_id', es.seat_id, 'seat', es.seat, 'min', es.min_count, 'max', es.max_count,
            'filled', (SELECT count(*) FROM person_entity_link l JOIN work_persona wp ON wp.persona_id = l.persona_id WHERE wp.seat_id = es.seat_id),
            'personas', (SELECT COALESCE(json_agg(wp.name), '[]') FROM work_persona wp WHERE wp.seat_id = es.seat_id),
            'people', (SELECT COALESCE(json_agg(user_name(l.person_id)), '[]') FROM person_entity_link l JOIN work_persona wp ON wp.persona_id = l.persona_id WHERE wp.seat_id = es.seat_id))
            ORDER BY es.seq), '[]') FROM entity_seat es WHERE es.entity_id = e);
END $$;

-- ---------- Entity Persona: applicability and the two forks ----------
ALTER TABLE persona_type ADD COLUMN legal_forms text[] NOT NULL DEFAULT '{}',          -- empty: every legal form
                         ADD COLUMN size_bands text[] NOT NULL DEFAULT '{}',           -- empty: every size
                         ADD COLUMN obligatory_domains text[] NOT NULL DEFAULT '{}',
                         ADD COLUMN non_obligatory_domains text[] NOT NULL DEFAULT '{}';

CREATE FUNCTION persona_path(t uuid) RETURNS text LANGUAGE sql STABLE AS $$
  WITH RECURSIVE up AS (SELECT persona_type_id, parent_id, display_name, depth FROM persona_type WHERE persona_type_id = t
                        UNION ALL SELECT p.persona_type_id, p.parent_id, p.display_name, p.depth FROM persona_type p JOIN up ON p.persona_type_id = up.parent_id)
  SELECT string_agg(display_name, ' › ' ORDER BY depth) FROM up
$$;

-- Entity Persona types that fit an entity: its activity root, legal form and size (empty lists mean any)
CREATE FUNCTION api_entity_personas(actor uuid, b jsonb) RETURNS json LANGUAGE sql STABLE AS $$
  SELECT COALESCE(json_agg(json_build_object('persona_type_id', pt.persona_type_id, 'path', persona_path(pt.persona_type_id), 'depth', pt.depth)
         ORDER BY persona_path(pt.persona_type_id)), '[]')
    FROM persona_type pt
   WHERE pt.party_type = 'Entity'
     AND (j(b, 'category') IS NULL OR lower(persona_path(pt.persona_type_id)) LIKE lower(j(b, 'category')) || '%')
     AND (cardinality(pt.legal_forms) = 0 OR j(b, 'legal_type') IS NULL OR j(b, 'legal_type') = ANY (pt.legal_forms))
     AND (cardinality(pt.size_bands) = 0 OR j(b, 'size') IS NULL OR j(b, 'size') = ANY (pt.size_bands))
$$;

CREATE FUNCTION api_set_entity_persona(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
DECLARE e uuid := (b->>'entity_id')::uuid;
BEGIN
  PERFORM need_admin(actor, e);
  UPDATE company SET persona_type_id = (b->>'persona_type_id')::uuid WHERE user_id = e;
  RETURN json_build_object('ok', true);
END $$;

-- The entity's persona, with what applies to it: obligatory and non-obligatory forks, inherited from its persona path
CREATE FUNCTION api_entity_persona(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql STABLE AS $$
DECLARE e uuid := (b->>'entity_id')::uuid; t uuid;
BEGIN
  PERFORM need_member(actor, e);
  SELECT persona_type_id INTO t FROM company WHERE user_id = e;
  RETURN (WITH RECURSIVE up AS (SELECT * FROM persona_type WHERE persona_type_id = t
                                UNION ALL SELECT p.* FROM persona_type p JOIN up ON p.persona_type_id = up.parent_id)
    SELECT json_build_object('path', persona_path(t),
      'legal_forms', (SELECT legal_forms FROM persona_type WHERE persona_type_id = t),
      'size_bands', (SELECT size_bands FROM persona_type WHERE persona_type_id = t),
      'obligatory', (SELECT COALESCE(json_agg(DISTINCT d), '[]') FROM up, unnest(up.obligatory_domains) d),
      'non_obligatory', (SELECT COALESCE(json_agg(DISTINCT d), '[]') FROM up, unnest(up.non_obligatory_domains) d),
      'description', (SELECT description FROM persona_type WHERE persona_type_id = t)));
END $$;

-- ---------- Domain persona: defined, not just a name (extends the workspace's own domain_persona) ----------
ALTER TABLE domain_persona ADD COLUMN obligatory boolean NOT NULL DEFAULT false,
                           ADD COLUMN requirements text,
                           ADD COLUMN permissible text[] NOT NULL DEFAULT '{}',
                           ADD COLUMN not_permissible text[] NOT NULL DEFAULT '{}',
                           ADD COLUMN seats text[] NOT NULL DEFAULT '{Fulfiller}';
UPDATE domain_persona dp SET obligatory = (d.catalogue = 'Compliance') FROM catalogue_domain d WHERE d.domain_id = dp.domain_id;

CREATE FUNCTION api_domain_personas(actor uuid, b jsonb) RETURNS json LANGUAGE sql STABLE AS $$
  SELECT COALESCE(json_agg(json_build_object('domain_persona_id', p.domain_persona_id, 'catalogue', d.catalogue, 'domain', d.name, 'name', p.name,
           'metadata', p.metadata, 'obligatory', p.obligatory, 'requirements', p.requirements, 'permissible', p.permissible,
           'not_permissible', p.not_permissible, 'seats', p.seats) ORDER BY d.catalogue, d.name, p.name), '[]')
    FROM domain_persona p JOIN catalogue_domain d USING (domain_id)
   WHERE j(b, 'catalogue') IS NULL OR d.catalogue = j(b, 'catalogue')
$$;

CREATE FUNCTION api_save_domain_persona(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
BEGIN
  IF NOT is_super(actor) THEN RAISE EXCEPTION 'Only the platform super-user defines domain personas'; END IF;
  UPDATE domain_persona SET obligatory = COALESCE((b->>'obligatory')::boolean, obligatory), requirements = j(b, 'requirements'),
         permissible = ARRAY(SELECT trim(x) FROM unnest(string_to_array(COALESCE(j(b, 'permissible'), ''), E'\n')) x WHERE trim(x) <> ''),
         not_permissible = ARRAY(SELECT trim(x) FROM unnest(string_to_array(COALESCE(j(b, 'not_permissible'), ''), E'\n')) x WHERE trim(x) <> ''),
         seats = ARRAY(SELECT jsonb_array_elements_text(COALESCE(b->'seats', '["Fulfiller"]')))
   WHERE domain_persona_id = (b->>'domain_persona_id')::uuid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Domain persona not found'; END IF;
  RETURN json_build_object('ok', true);
END $$;

-- ---------- Human Persona: a person counterparty resolves Kramas through the person's persona ----------
ALTER TABLE users ADD COLUMN persona_type_id uuid REFERENCES persona_type(persona_type_id);
UPDATE users SET persona_type_id = (SELECT persona_type_id FROM persona_type WHERE slug = 'human_placeholder') WHERE user_type = 'Individual';

CREATE OR REPLACE FUNCTION resolve_kramas(p_item uuid, p_relationship text, p_counterparty uuid) RETURNS SETOF uuid LANGUAGE sql STABLE AS $$
  SELECT ck.krama_id FROM catalogue_item_krama ck
   WHERE ck.item_id = p_item AND (
     (NOT is_external(ck.krama_id) AND p_relationship IN ('Department','Business Unit'))
     OR (is_external(ck.krama_id) AND p_counterparty IS NOT NULL AND EXISTS (
          SELECT 1 FROM krama_relationship m
           WHERE m.krama_id IN (ck.krama_id, matrix_root(ck.krama_id))
             AND m.relationship = p_relationship
             AND ((m.party_type = 'Entity' AND persona_within((SELECT persona_type_id FROM company WHERE user_id = p_counterparty), m.persona_type_id))
               OR (m.party_type = 'Person' AND persona_within((SELECT persona_type_id FROM users WHERE user_id = p_counterparty AND user_type = 'Individual'), m.persona_type_id))))))
$$;

-- ---------- sample Work Personas for the sample people, so the sample flows keep working ----------
DO $$
DECLARE led uuid; fin uuid; head uuid; exec uuid;
BEGIN
  SELECT user_id INTO led FROM users WHERE name = 'Ledgerline Traders';
  SELECT dept_bu_id INTO fin FROM dept_bu WHERE company_user_id = led AND name = 'Finance';
  SELECT persona_id INTO head FROM work_persona WHERE entity_id = led AND name = 'Finance Head';
  SELECT persona_id INTO exec FROM work_persona WHERE entity_id = led AND name = 'Accounts Executive';
  UPDATE work_persona SET modules = ARRAY['WOM','Krama','Catalogue','Vendors','Reports'], actions = ARRAY['View','Approve','Sign'] WHERE persona_id = head;
  UPDATE work_persona SET modules = ARRAY['WOM','Catalogue','Vendors'], actions = ARRAY['View'] WHERE persona_id = exec;
  UPDATE person_entity_link SET persona_id = head WHERE company_user_id = led AND person_id = (SELECT user_id FROM users WHERE name = 'Ravi Kumar');
  UPDATE person_entity_link SET persona_id = exec WHERE company_user_id = led AND person_id = (SELECT user_id FROM users WHERE name = 'Priya Nair');
  -- The sample Finance Head attaches to the entity's first authority seat (Partners, for the sample partnership firm)
  UPDATE work_persona wp SET seat_id = (SELECT es.seat_id FROM entity_seat es WHERE es.entity_id = wp.entity_id ORDER BY es.seq LIMIT 1)
   WHERE wp.persona_id = head;
END $$;
-- Sample persona applicability, for the sample entities' types only
UPDATE persona_type SET non_obligatory_domains = '{Office consumables,Expense management}', obligatory_domains = '{GST}' WHERE slug = 'trading';


-- ---------- Work Personas screen (classic Settings) ----------
-- Work Personas screen: Dept/BUs with grades and personas, people with their persona
CREATE FUNCTION api_work_personas(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql STABLE AS $$
DECLARE e uuid := (b->>'entity_id')::uuid;
BEGIN
  PERFORM need_member(actor, e);
  RETURN json_build_object('is_admin', is_entity_super(actor, e) OR is_super(actor), 'my_admin_dept', admin_dept(actor, e),
    'dept_bus', (SELECT COALESCE(json_agg(json_build_object('dept_bu_id', d.dept_bu_id, 'name', d.name,
        'grades', (SELECT COALESCE(json_agg(json_build_object('grade_id', g.grade_id, 'name', g.name) ORDER BY g.rank), '[]') FROM grade g WHERE g.dept_bu_id = d.dept_bu_id),
        'personas', (SELECT COALESCE(json_agg(json_build_object('persona_id', p.persona_id, 'name', p.name, 'grade', (SELECT name FROM grade WHERE grade_id = p.grade_id),
                      'reports_to', (SELECT name FROM work_persona r WHERE r.persona_id = p.reports_to), 'modules', p.modules, 'actions', p.actions,
                      'seat', (SELECT seat FROM entity_seat WHERE seat_id = p.seat_id), 'seat_id', p.seat_id) ORDER BY p.name), '[]')
                     FROM work_persona p WHERE p.dept_bu_id = d.dept_bu_id)) ORDER BY d.name), '[]') FROM dept_bu d WHERE d.company_user_id = e),
    'people', (SELECT COALESCE(json_agg(json_build_object('link_id', l.link_id, 'name', user_name(l.person_id), 'admin', l.is_entity_super_user,
                'dept_bu_id', l.dept_bu_id, 'dept_admin', l.is_dept_admin,
                'dept_bu', (SELECT name FROM dept_bu WHERE dept_bu_id = l.dept_bu_id), 'persona_id', l.persona_id,
                'persona', (SELECT name FROM work_persona WHERE persona_id = l.persona_id)) ORDER BY user_name(l.person_id)), '[]')
              FROM person_entity_link l WHERE l.company_user_id = e));
END $$;

CREATE FUNCTION api_assign_persona(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
DECLARE l record;
BEGIN
  SELECT * INTO l FROM person_entity_link WHERE link_id = (b->>'link_id')::uuid;
  IF l.link_id IS NULL THEN RAISE EXCEPTION 'Person not found in this entity'; END IF;
  PERFORM need_dept_rights(actor, l.company_user_id, l.dept_bu_id);
  IF NULLIF(b->>'persona_id', '') IS NOT NULL AND NOT is_entity_super(actor, l.company_user_id)
     AND (SELECT dept_bu_id FROM work_persona WHERE persona_id = (b->>'persona_id')::uuid) IS DISTINCT FROM l.dept_bu_id THEN
    RAISE EXCEPTION 'A Dept/BU admin picks from their own Dept/BU''s Work Personas';
  END IF;
  UPDATE person_entity_link SET persona_id = NULLIF(b->>'persona_id', '')::uuid WHERE link_id = l.link_id;
  RETURN json_build_object('ok', true);
END $$;
