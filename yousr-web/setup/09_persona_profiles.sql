-- =====================================================================================
-- Persona, Role, Responsibility and Permission kept separate (from the two persona files):
--  1. Permission: each person's own modules and actions; a Work Persona only suggests a default.
--  2. Person Persona: who the individual is professionally (kept on the person, in Yousr).
--  3. Domain Profile: the subject area itself, above its domain personas.
--  4. Entity Profile: objectives and capabilities added to the Entity Persona.
--  5. Responsibility: bearer, fulfiller and auditor recorded against named people or vendors.
-- Roles (task seats and catalogue item seats) are unchanged.
-- =====================================================================================

-- ---------- 1. Permission ----------
CREATE TABLE person_permission (
  link_id uuid PRIMARY KEY REFERENCES person_entity_link(link_id) ON DELETE CASCADE,
  modules text[] NOT NULL,
  actions text[] NOT NULL
);

-- What a person may see and do: entity admin has everything; else their own Permission;
-- else the default Permission of their Work Persona; else WOM and View
CREATE OR REPLACE FUNCTION person_access(p uuid, e uuid) RETURNS json LANGUAGE sql STABLE AS $$
  SELECT CASE
    WHEN is_super(p) OR is_entity_super(p, e) THEN json_build_object('admin', true, 'modules', all_modules(), 'actions', ARRAY['View','Approve','Sign'],
                                                                     'persona', 'Entity admin', 'source', 'Entity admin')
    WHEN pp.link_id IS NOT NULL THEN json_build_object('admin', false, 'modules', pp.modules, 'actions', pp.actions, 'persona', wp.name, 'source', 'Own Permission')
    WHEN wp.persona_id IS NOT NULL THEN json_build_object('admin', false, 'modules', wp.modules, 'actions', wp.actions, 'persona', wp.name, 'source', 'Default from Work Persona')
    ELSE json_build_object('admin', false, 'modules', ARRAY['WOM'], 'actions', ARRAY['View'], 'persona', NULL, 'source', 'Platform default') END
  FROM (SELECT 1) one
  LEFT JOIN person_entity_link l ON l.person_id = p AND l.company_user_id = e
  LEFT JOIN work_persona wp ON wp.persona_id = l.persona_id
  LEFT JOIN person_permission pp ON pp.link_id = l.link_id
$$;

CREATE FUNCTION api_set_permission(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
DECLARE l record; m text; a text;
BEGIN
  SELECT * INTO l FROM person_entity_link WHERE link_id = (b->>'link_id')::uuid;
  IF l IS NULL THEN RAISE EXCEPTION 'Person not found in this entity'; END IF;
  PERFORM need_admin(actor, l.company_user_id);
  IF COALESCE((b->>'use_default')::boolean, false) THEN
    DELETE FROM person_permission WHERE link_id = l.link_id;
    RETURN json_build_object('ok', true);
  END IF;
  FOR m IN SELECT jsonb_array_elements_text(COALESCE(b->'modules', '[]')) LOOP
    IF NOT m = ANY (all_modules()) THEN RAISE EXCEPTION 'Unknown module %', m; END IF;
  END LOOP;
  FOR a IN SELECT jsonb_array_elements_text(COALESCE(b->'actions', '[]')) LOOP
    IF a NOT IN ('View','Approve','Sign') THEN RAISE EXCEPTION 'Actions are View, Approve and Sign'; END IF;
  END LOOP;
  INSERT INTO person_permission (link_id, modules, actions)
  VALUES (l.link_id, ARRAY(SELECT jsonb_array_elements_text(COALESCE(b->'modules', '[]'))), ARRAY(SELECT jsonb_array_elements_text(COALESCE(b->'actions', '[]'))))
  ON CONFLICT (link_id) DO UPDATE SET modules = EXCLUDED.modules, actions = EXCLUDED.actions;
  RETURN json_build_object('ok', true);
END $$;

-- Each person's Permission as it now applies, for the Work Personas screen
CREATE FUNCTION api_permissions(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql STABLE AS $$
DECLARE e uuid := (b->>'entity_id')::uuid;
BEGIN
  PERFORM need_member(actor, e);
  RETURN (SELECT COALESCE(json_agg(json_build_object('link_id', l.link_id, 'person_id', l.person_id, 'name', user_name(l.person_id), 'access', person_access(l.person_id, e), 'own', EXISTS (SELECT 1 FROM person_permission pp WHERE pp.link_id = l.link_id)) ORDER BY user_name(l.person_id)), '[]')
            FROM person_entity_link l WHERE l.company_user_id = e);
END $$;

-- ---------- 2. Person Persona (areas of expertise stay on the person, users.expertise_ids, which seat matching already uses) ----------
CREATE TABLE person_persona (
  person_id                 uuid PRIMARY KEY REFERENCES users(user_id) ON DELETE CASCADE,
  professional_identity     text,
  skills                    text[] NOT NULL DEFAULT '{}',
  experience                text,
  functional_interests      text[] NOT NULL DEFAULT '{}',
  working_preferences       text,
  communication_preferences text
);

CREATE FUNCTION lines(t text) RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
  SELECT ARRAY(SELECT trim(x) FROM unnest(string_to_array(COALESCE(t, ''), E'\n')) x WHERE trim(x) <> '')
$$;

CREATE FUNCTION api_person_persona(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
DECLARE p uuid := COALESCE(NULLIF(b->>'person_id', '')::uuid, actor);
BEGIN
  PERFORM need(actor);
  IF b ? 'save' THEN
    IF p <> actor THEN RAISE EXCEPTION 'You edit only your own Person Persona'; END IF;
    UPDATE users SET expertise_ids = ARRAY(SELECT jsonb_array_elements_text(COALESCE(b->'save'->'expertise_ids', '[]'))::uuid) WHERE user_id = p;
    INSERT INTO person_persona (person_id, professional_identity, skills, experience, functional_interests, working_preferences, communication_preferences)
    VALUES (p, j(b->'save', 'professional_identity'), lines(b->'save'->>'skills'), j(b->'save', 'experience'),
            lines(b->'save'->>'functional_interests'), j(b->'save', 'working_preferences'), j(b->'save', 'communication_preferences'))
    ON CONFLICT (person_id) DO UPDATE SET professional_identity = EXCLUDED.professional_identity, skills = EXCLUDED.skills,
       experience = EXCLUDED.experience, functional_interests = EXCLUDED.functional_interests, working_preferences = EXCLUDED.working_preferences,
       communication_preferences = EXCLUDED.communication_preferences;
  END IF;
  RETURN json_build_object('name', user_name(p),
    'persona', (SELECT row_to_json(pp) FROM person_persona pp WHERE pp.person_id = p),
    'expertise_ids', (SELECT expertise_ids FROM users WHERE user_id = p),
    'expertise', (SELECT COALESCE(json_agg(json_build_object('expertise_id', x.expertise_id, 'name', x.name) ORDER BY x.name), '[]') FROM expertise x));
END $$;

-- ---------- 3. Domain Profile ----------
CREATE TABLE domain_profile (
  domain_id               uuid PRIMARY KEY REFERENCES catalogue_domain(domain_id) ON DELETE CASCADE,
  objectives              text,
  terminology             text[] NOT NULL DEFAULT '{}',
  regulations             text[] NOT NULL DEFAULT '{}',
  typical_workflows       text[] NOT NULL DEFAULT '{}',
  controls                text[] NOT NULL DEFAULT '{}',
  compliance_requirements text
);

CREATE FUNCTION api_domain_profiles(actor uuid, b jsonb) RETURNS json LANGUAGE sql STABLE AS $$
  SELECT COALESCE(json_agg(json_build_object('domain_id', d.domain_id, 'catalogue', d.catalogue, 'name', d.name, 'profile', (SELECT row_to_json(dp) FROM domain_profile dp WHERE dp.domain_id = d.domain_id),
           'personas', (SELECT COALESCE(json_agg(p.name ORDER BY p.name), '[]') FROM domain_persona p WHERE p.domain_id = d.domain_id)) ORDER BY d.catalogue, d.name), '[]')
    FROM catalogue_domain d
$$;

CREATE FUNCTION api_save_domain_profile(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
BEGIN
  IF NOT is_super(actor) THEN RAISE EXCEPTION 'Only the platform super-user defines domain profiles'; END IF;
  INSERT INTO domain_profile (domain_id, objectives, terminology, regulations, typical_workflows, controls, compliance_requirements)
  VALUES ((b->>'domain_id')::uuid, j(b, 'objectives'), lines(b->>'terminology'), lines(b->>'regulations'), lines(b->>'typical_workflows'), lines(b->>'controls'), j(b, 'compliance_requirements'))
  ON CONFLICT (domain_id) DO UPDATE SET objectives = EXCLUDED.objectives, terminology = EXCLUDED.terminology, regulations = EXCLUDED.regulations,
     typical_workflows = EXCLUDED.typical_workflows, controls = EXCLUDED.controls, compliance_requirements = EXCLUDED.compliance_requirements;
  RETURN json_build_object('ok', true);
END $$;

-- ---------- 4. Entity Profile ----------
ALTER TABLE company ADD COLUMN objectives text, ADD COLUMN capabilities text[] NOT NULL DEFAULT '{}';

CREATE FUNCTION api_entity_profile(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
DECLARE e uuid := (b->>'entity_id')::uuid;
BEGIN
  IF b ? 'save' THEN
    PERFORM need_admin(actor, e);
    UPDATE company SET objectives = j(b->'save', 'objectives'), capabilities = lines(b->'save'->>'capabilities') WHERE user_id = e;
  ELSE PERFORM need_member(actor, e);
  END IF;
  RETURN (SELECT json_build_object('objectives', objectives, 'capabilities', capabilities) FROM company WHERE user_id = e);
END $$;

-- ---------- 5. Responsibility ----------
CREATE TABLE responsibility (
  responsibility_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_id         uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  item_id           uuid REFERENCES catalogue_item(item_id) ON DELETE CASCADE,
  obligation        text NOT NULL,
  kind              text NOT NULL CHECK (kind IN ('Bearer','Fulfiller','Auditor')),
  person_id         uuid REFERENCES users(user_id),      -- a person in a Dept/BU
  vendor_id         uuid REFERENCES users(user_id),      -- or a vendor (Fulfiller or Auditor)
  CHECK ((person_id IS NULL) <> (vendor_id IS NULL) OR kind = 'Bearer')
);

CREATE FUNCTION api_responsibilities(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
DECLARE e uuid := (b->>'entity_id')::uuid; it uuid;
BEGIN
  IF j(b, 'add') IS NOT NULL THEN
    PERFORM need_admin(actor, e);
    IF j(b->'add', 'kind') NOT IN ('Bearer','Fulfiller','Auditor') THEN RAISE EXCEPTION 'Pick Bearer, Fulfiller or Auditor'; END IF;
    IF j(b->'add', 'obligation') IS NULL AND j(b->'add', 'item_id') IS NULL THEN RAISE EXCEPTION 'Name the obligation or pick the catalogue item'; END IF;
    it := NULLIF(b->'add'->>'item_id', '')::uuid;
    IF j(b->'add', 'kind') <> 'Bearer' AND j(b->'add', 'person_id') IS NULL AND j(b->'add', 'vendor_id') IS NULL THEN
      RAISE EXCEPTION 'Name the person or the vendor';
    END IF;
    IF j(b->'add', 'kind') = 'Auditor' AND EXISTS (SELECT 1 FROM responsibility r WHERE r.entity_id = e AND r.kind = 'Fulfiller'
         AND r.item_id IS NOT DISTINCT FROM it AND (r.person_id = NULLIF(b->'add'->>'person_id', '')::uuid OR r.vendor_id = NULLIF(b->'add'->>'vendor_id', '')::uuid)) THEN
      RAISE EXCEPTION 'The auditor is never the fulfiller of the same obligation';
    END IF;
    INSERT INTO responsibility (entity_id, item_id, obligation, kind, person_id, vendor_id)
    VALUES (e, it, COALESCE(j(b->'add', 'obligation'), (SELECT name FROM catalogue_item WHERE item_id = it)), j(b->'add', 'kind'),
            NULLIF(b->'add'->>'person_id', '')::uuid, NULLIF(b->'add'->>'vendor_id', '')::uuid);
  END IF;
  IF j(b, 'remove') IS NOT NULL THEN
    PERFORM need_admin(actor, e);
    DELETE FROM responsibility WHERE responsibility_id = (b->>'remove')::uuid AND entity_id = e;
  END IF;
  PERFORM need_member(actor, e);
  RETURN (SELECT COALESCE(json_agg(json_build_object('responsibility_id', r.responsibility_id, 'obligation', r.obligation, 'kind', r.kind,
            'item', (SELECT name FROM catalogue_item WHERE item_id = r.item_id),
            'who', COALESCE(user_name(r.person_id), user_name(r.vendor_id), CASE WHEN r.kind = 'Bearer' THEN user_name(r.entity_id) END),
            'who_kind', CASE WHEN r.person_id IS NOT NULL THEN 'Person' WHEN r.vendor_id IS NOT NULL THEN 'Vendor' ELSE 'Entity' END)
            ORDER BY r.obligation, CASE r.kind WHEN 'Bearer' THEN 1 WHEN 'Fulfiller' THEN 2 ELSE 3 END), '[]')
            FROM responsibility r WHERE r.entity_id = e);
END $$;

-- ---------- sample data for the sample entity ----------
DO $$
DECLARE led uuid; ravi uuid; priya uuid; item uuid; nw uuid;
BEGIN
  SELECT user_id INTO led FROM users WHERE name = 'Ledgerline Traders';
  SELECT user_id INTO ravi FROM users WHERE name = 'Ravi Kumar';
  SELECT user_id INTO priya FROM users WHERE name = 'Priya Nair';
  SELECT user_id INTO nw FROM users WHERE name = 'Northwind Supplies';
  SELECT item_id INTO item FROM catalogue_item WHERE company_user_id = led AND catalogue = 'Compliance' LIMIT 1;
  IF item IS NOT NULL THEN
    INSERT INTO responsibility (entity_id, item_id, obligation, kind) SELECT led, item, name, 'Bearer' FROM catalogue_item WHERE item_id = item;
    INSERT INTO responsibility (entity_id, item_id, obligation, kind, person_id) SELECT led, item, name, 'Fulfiller', priya FROM catalogue_item WHERE item_id = item;
    INSERT INTO responsibility (entity_id, item_id, obligation, kind, person_id) SELECT led, item, name, 'Auditor', ravi FROM catalogue_item WHERE item_id = item;
  END IF;
  INSERT INTO person_persona (person_id, professional_identity, skills, experience)
  VALUES (ravi, 'Finance professional', '{Vendor payments,Month-end close}', '12 years in finance');
END $$;
