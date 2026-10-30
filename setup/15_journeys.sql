-- =====================================================================================
-- User journeys (living document) and the Work Persona doctrine:
--  - Role, responsibility and permission are one thing: the Work Persona (set per Dept/BU).
--  - Registration is email only; the new person lands in Personal with a task to update their profile.
--  - Dept/BU admins (one per Dept/BU) set Work Personas and set up their Dept/BU's catalogue.
--  - A new entity gets a task to complete its client listing (client entity, user name, user email).
-- =====================================================================================

-- ---------- Permission folded back into the Work Persona ----------
DROP FUNCTION IF EXISTS api_set_permission(uuid, jsonb);
DROP TABLE IF EXISTS person_permission;
CREATE OR REPLACE FUNCTION person_access(p uuid, e uuid) RETURNS json LANGUAGE sql STABLE AS $$
  SELECT CASE
    WHEN is_super(p) OR is_entity_super(p, e) THEN json_build_object('admin', true, 'modules', all_modules(), 'actions', ARRAY['View','Approve','Sign'],
                                                                     'persona', 'Entity admin', 'source', 'Entity admin')
    WHEN wp.persona_id IS NOT NULL THEN json_build_object('admin', false, 'modules', wp.modules, 'actions', wp.actions, 'persona', wp.name, 'source', 'Work Persona')
    ELSE json_build_object('admin', false, 'modules', ARRAY['WOM'], 'actions', ARRAY['View'], 'persona', NULL, 'source', 'No Work Persona yet') END
  FROM (SELECT 1) one
  LEFT JOIN person_entity_link l ON l.person_id = p AND l.company_user_id = e
  LEFT JOIN work_persona wp ON wp.persona_id = l.persona_id
$$;
CREATE OR REPLACE FUNCTION api_permissions(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql STABLE AS $$
DECLARE e uuid := (b->>'entity_id')::uuid;
BEGIN
  PERFORM need_member(actor, e);
  RETURN (SELECT COALESCE(json_agg(json_build_object('link_id', l.link_id, 'person_id', l.person_id, 'name', user_name(l.person_id),
            'dept_bu_id', l.dept_bu_id, 'dept_bu', (SELECT name FROM dept_bu WHERE dept_bu_id = l.dept_bu_id), 'dept_admin', l.is_dept_admin,
            'admin', l.is_entity_super_user, 'access', person_access(l.person_id, e)) ORDER BY user_name(l.person_id)), '[]')
            FROM person_entity_link l WHERE l.company_user_id = e);
END $$;

-- ---------- Dept/BU admin and moving people between Dept/BUs (entity admin) ----------
CREATE FUNCTION api_set_dept_admin(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
DECLARE l record;
BEGIN
  SELECT * INTO l FROM person_entity_link WHERE link_id = (b->>'link_id')::uuid;
  IF l.link_id IS NULL THEN RAISE EXCEPTION 'Person not found in this entity'; END IF;
  PERFORM need_admin(actor, l.company_user_id);
  IF COALESCE((b->>'on')::boolean, true) THEN
    IF l.dept_bu_id IS NULL THEN RAISE EXCEPTION 'Put the person in a Dept/BU first'; END IF;
    UPDATE person_entity_link SET is_dept_admin = false WHERE dept_bu_id = l.dept_bu_id AND link_id <> l.link_id;
    UPDATE person_entity_link SET is_dept_admin = true WHERE link_id = l.link_id;
  ELSE
    UPDATE person_entity_link SET is_dept_admin = false WHERE link_id = l.link_id;
  END IF;
  RETURN json_build_object('ok', true);
END $$;

CREATE FUNCTION api_set_member_dept(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
DECLARE l record; d uuid := NULLIF(b->>'dept_bu_id', '')::uuid;
BEGIN
  SELECT * INTO l FROM person_entity_link WHERE link_id = (b->>'link_id')::uuid;
  IF l.link_id IS NULL THEN RAISE EXCEPTION 'Person not found in this entity'; END IF;
  PERFORM need_admin(actor, l.company_user_id);
  IF d IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dept_bu WHERE dept_bu_id = d AND company_user_id = l.company_user_id) THEN RAISE EXCEPTION 'That Dept/BU is not this entity''s'; END IF;
  -- Moving Dept/BU ends their Dept/BU admin role and their Work Persona there (personas belong to a Dept/BU)
  UPDATE person_entity_link SET dept_bu_id = d, is_dept_admin = false,
         persona_id = CASE WHEN (SELECT dept_bu_id FROM work_persona WHERE persona_id = l.persona_id) IS NOT DISTINCT FROM d THEN persona_id END
   WHERE link_id = l.link_id;
  RETURN json_build_object('ok', true);
END $$;

-- ---------- Registration: email only; the profile task on Personal ----------
ALTER TABLE personal_task ADD COLUMN action text;
ALTER TABLE standalone_task ADD COLUMN action text;

CREATE OR REPLACE FUNCTION api_access(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
DECLARE u record; uid uuid; cid text; nm text;
BEGIN
  PERFORM otp_ok(j(b, 'email'), 'access', j(b, 'code'));
  SELECT * INTO u FROM users WHERE lower(personal_email) = lower(j(b, 'email')) AND user_type = 'Individual';
  IF u.user_id IS NOT NULL THEN RETURN json_build_object('user_id', u.user_id, 'name', u.name); END IF;
  IF free_domain(j(b, 'email')) IS NOT TRUE THEN
    RAISE EXCEPTION 'A Yousr account uses your personal email (Gmail, Outlook and similar). Work emails come later, inside an entity.';
  END IF;
  -- New person: the account is created from the email alone; the name is filled in later from the profile task
  nm := initcap(regexp_replace(split_part(lower(j(b, 'email')), '@', 1), '[._0-9-]+', ' ', 'g'));
  cid := 'CMP-' || upper(substr(md5(random()::text), 1, 6));
  INSERT INTO users (name, personal_email, compane_id) VALUES (trim(nm), lower(j(b, 'email')), cid) RETURNING user_id INTO uid;
  INSERT INTO personal_document (owner_id, kind) VALUES (uid, 'National ID'), (uid, 'Tax ID'), (uid, 'Passport');
  INSERT INTO personal_task (owner_id, title, purpose, quadrant, action)
  VALUES (uid, 'Update your personal profile', 'Your name and photo', 'Do now', 'profile');
  RETURN json_build_object('user_id', uid, 'name', trim(nm), 'created', true, 'compane_id', cid);
END $$;

-- Saving the profile closes the profile task
CREATE OR REPLACE FUNCTION api_profile(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
BEGIN
  PERFORM need(actor);
  IF j(b, 'name') IS NOT NULL THEN
    UPDATE users SET name = j(b, 'name'), photo = j(b, 'photo') WHERE user_id = actor;
    UPDATE personal_task SET status = 'Done', done_at = clock_timestamp() WHERE owner_id = actor AND action = 'profile' AND status = 'To do';
  END IF;
  RETURN (SELECT json_build_object('name', name, 'photo', photo, 'personal_email', personal_email, 'mobile', mobile, 'compane_id', compane_id)
            FROM users WHERE user_id = actor);
END $$;

-- ---------- Client listing ----------
ALTER TABLE entity_connection ADD COLUMN contact_name text, ADD COLUMN contact_email text;

CREATE FUNCTION api_add_client(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
DECLARE e uuid := (b->>'entity_id')::uuid; t uuid;
BEGIN
  PERFORM need_member(actor, e);
  IF NOT can_edit_catalogue(actor, e) THEN RAISE EXCEPTION 'Only the entity admin or a Dept/BU admin adds clients'; END IF;
  IF j(b, 'user_email') IS NOT NULL AND NOT valid_email(j(b, 'user_email')) THEN RAISE EXCEPTION 'Enter a valid email for the client''s user'; END IF;
  -- An existing business picked from the search, or a new entry by name (matched to a business of exactly that name, if any)
  IF j(b, 'client_entity_id') IS NOT NULL THEN
    SELECT user_id INTO t FROM users WHERE user_id = (b->>'client_entity_id')::uuid AND user_type = 'Company' AND can_accept(user_id);
    IF t IS NULL THEN RAISE EXCEPTION 'That business has nobody who can accept a connection yet; add it as a new client'; END IF;
  ELSE
    IF j(b, 'client_name') IS NULL THEN RAISE EXCEPTION 'Enter the client entity name, or pick an existing business'; END IF;
    -- linked only if someone there can accept; otherwise listed as a new client
    SELECT user_id INTO t FROM users WHERE user_type = 'Company' AND lower(name) = lower(j(b, 'client_name')) AND can_accept(user_id);
  END IF;
  IF t = e THEN RAISE EXCEPTION 'An entity cannot list itself as a client'; END IF;
  IF EXISTS (SELECT 1 FROM entity_connection WHERE failure IS NULL
               AND ((from_entity = e AND (to_entity = t OR lower(to_name) = lower(COALESCE(user_name(t), j(b, 'client_name')))))
                 OR (from_entity = t AND to_entity = e))) THEN
    RAISE EXCEPTION 'This business is already in your list';
  END IF;
  INSERT INTO entity_connection (from_entity, to_entity, to_name, relationship, state, invited_by, contact_name, contact_email)
  VALUES (e, t, COALESCE(user_name(t), j(b, 'client_name')), 'Client', CASE WHEN t IS NULL THEN 'Standalone' ELSE 'Pending' END, actor,
          j(b, 'user_name'), lower(j(b, 'user_email')));
  RETURN json_build_object('ok', true, 'on_platform', t IS NOT NULL);
END $$;

CREATE FUNCTION api_clients(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql STABLE AS $$
DECLARE e uuid := (b->>'entity_id')::uuid;
BEGIN
  PERFORM need_member(actor, e);
  RETURN (SELECT COALESCE(json_agg(json_build_object('name', c.to_name, 'user_name', c.contact_name, 'user_email', c.contact_email, 'state', c.state,
            'on_platform', c.to_entity IS NOT NULL) ORDER BY c.to_name), '[]')
            FROM entity_connection c WHERE c.from_entity = e AND c.relationship IN ('Client','Pre-client') AND c.failure IS NULL);
END $$;

-- A new entity gets the task to complete its client listing
CREATE OR REPLACE FUNCTION add_client_listing_task() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.is_entity_super_user AND NOT EXISTS (SELECT 1 FROM standalone_task WHERE company_user_id = NEW.company_user_id AND action = 'client_listing') THEN
    INSERT INTO standalone_task (owner_id, company_user_id, title, notes, quadrant, action)
    VALUES (NEW.person_id, NEW.company_user_id, 'Complete your client listing', 'Client entity name, user name and user email', 'Do now', 'client_listing');
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER add_client_listing_task AFTER INSERT ON person_entity_link FOR EACH ROW EXECUTE FUNCTION add_client_listing_task();

-- Sample: Ledgerline's Finance admin, and its client listing task
UPDATE person_entity_link SET is_dept_admin = true
 WHERE company_user_id = '11111111-0000-0000-0000-000000000012' AND person_id = (SELECT user_id FROM users WHERE name = 'Ravi Kumar');
INSERT INTO standalone_task (owner_id, company_user_id, title, notes, quadrant, action)
SELECT l.person_id, l.company_user_id, 'Complete your client listing', 'Client entity name, user name and user email', 'Do now', 'client_listing'
  FROM person_entity_link l WHERE l.company_user_id = '11111111-0000-0000-0000-000000000012' AND l.is_entity_super_user
   AND NOT EXISTS (SELECT 1 FROM standalone_task s WHERE s.company_user_id = l.company_user_id AND s.action = 'client_listing')
 LIMIT 1;

-- Open journey tasks for the signed-in person: the profile task (Personal) and client listing tasks (entities)
CREATE FUNCTION api_my_actions(actor uuid, b jsonb) RETURNS json LANGUAGE sql STABLE AS $$
  SELECT json_build_object(
    'profile', EXISTS (SELECT 1 FROM personal_task WHERE owner_id = actor AND action = 'profile' AND status = 'To do'),
    'client_listing', (SELECT COALESCE(json_agg(json_build_object('task_id', task_id, 'entity_id', company_user_id)), '[]')
                         FROM standalone_task WHERE owner_id = actor AND action = 'client_listing' AND status = 'Open'))
$$;
CREATE FUNCTION api_finish_task(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
BEGIN
  PERFORM mark_done((b->>'task_id')::uuid, actor);
  RETURN json_build_object('ok', true);
END $$;
