-- =====================================================================================
-- Platform: sign-in and the building blocks, Settings, Files, ID, Discover and Connect,
-- Revenue, Compliance, Tools, Email, Chat, Search, and Krama Phase 4.
-- Every screen action is an api_<name>(actor, body) function returning json.
-- =====================================================================================

-- Krama kinds (Phase 4) on the workspace schema
ALTER TABLE krama ADD COLUMN kind text NOT NULL DEFAULT 'Workflow' CHECK (kind IN ('Workflow','Report and Analytics','Module')),
                  ADD COLUMN standalone boolean NOT NULL DEFAULT false;
ALTER TABLE report ADD COLUMN metric text NOT NULL DEFAULT 'questions_by_state'
  CHECK (metric IN ('runs_by_status','questions_by_state','overdue_questions','runs_by_item','estimate_totals'));

-- ---------- people and entities: the fields the building blocks capture ----------
ALTER TABLE users ADD COLUMN mobile text, ADD COLUMN compane_id text UNIQUE, ADD COLUMN photo text,
                  ADD COLUMN identity_verified boolean NOT NULL DEFAULT false;
ALTER TABLE company ADD COLUMN country text NOT NULL DEFAULT 'India', ADD COLUMN work_email text, ADD COLUMN admin_personal_email text,
                    ADD COLUMN category text, ADD COLUMN sub_category text, ADD COLUMN size text, ADD COLUMN business_model text,
                    ADD COLUMN corporate_doc text, ADD COLUMN authorised_email text, ADD COLUMN entity_mobile text,
                    ADD COLUMN complete_setup jsonb NOT NULL DEFAULT '{}'::jsonb, ADD COLUMN connection_hub jsonb NOT NULL DEFAULT '{}'::jsonb,
                    ADD COLUMN delete_requested_at timestamptz;
ALTER TABLE person_entity_link ADD COLUMN work_email text, ADD COLUMN designation text, ADD COLUMN sits text, ADD COLUMN persona_id uuid;

-- One-time codes. In the demo the code is returned to the screen; on the platform it goes by email or SMS.
CREATE TABLE otp_code (
  otp_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  target   text NOT NULL,
  purpose  text NOT NULL,
  code     text NOT NULL,
  used     boolean NOT NULL DEFAULT false,
  at       timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE entity_invite (
  invite_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_id   uuid NOT NULL REFERENCES users(user_id),
  work_email  text NOT NULL,
  name        text NOT NULL,
  mobile      text,
  designation text,
  dept_bu_id  uuid REFERENCES dept_bu(dept_bu_id),
  sits        text NOT NULL CHECK (sits IN ('Admin above Dept/BU head','Dept/BU head or below')),
  status      text NOT NULL DEFAULT 'Pending' CHECK (status IN ('Pending','Accepted','Declined','Lapsed','Cancelled')),
  sent_by     uuid REFERENCES users(user_id),
  at          timestamptz NOT NULL DEFAULT clock_timestamp()
);

-- Entity to entity: relationship label and connection state are separate
CREATE TABLE entity_connection (
  connection_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  from_entity   uuid NOT NULL REFERENCES users(user_id),
  to_entity     uuid REFERENCES users(user_id),
  to_name       text NOT NULL,
  relationship  text NOT NULL CHECK (relationship IN ('Pre-client','Client','Pre-vendor','Vendor')),
  state         text NOT NULL DEFAULT 'Pending' CHECK (state IN ('Standalone','Pending','Connected')),
  failure       text CHECK (failure IN ('Expired','Cancelled')),
  resent        integer NOT NULL DEFAULT 0,
  invited_by    uuid REFERENCES users(user_id),
  at            timestamptz NOT NULL DEFAULT clock_timestamp()
);

-- Settings: grades, designations and Work Personas, per Dept/BU
CREATE TABLE grade (
  grade_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  dept_bu_id uuid NOT NULL REFERENCES dept_bu(dept_bu_id) ON DELETE CASCADE,
  name       text NOT NULL,
  rank       integer NOT NULL
);
CREATE TABLE designation (
  designation_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  dept_bu_id     uuid NOT NULL REFERENCES dept_bu(dept_bu_id) ON DELETE CASCADE,
  grade_id       uuid REFERENCES grade(grade_id) ON DELETE SET NULL,
  name           text NOT NULL
);
CREATE TABLE work_persona (
  persona_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_id    uuid NOT NULL REFERENCES users(user_id),
  dept_bu_id   uuid REFERENCES dept_bu(dept_bu_id) ON DELETE CASCADE,
  grade_id     uuid REFERENCES grade(grade_id) ON DELETE SET NULL,
  name         text NOT NULL,
  reports_to   uuid REFERENCES work_persona(persona_id),
  is_exception boolean NOT NULL DEFAULT false,
  modules      text[] NOT NULL DEFAULT '{WOM}'
);

-- My ID: personal identity documents, verified through DigiLocker only
CREATE TABLE personal_document (
  doc_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES users(user_id),
  kind     text NOT NULL,
  status   text NOT NULL DEFAULT 'Not connected' CHECK (status IN ('Not connected','Verified')),
  at       timestamptz
);

-- Chat: one conversation per pair of parties (a person or an entity on either side)
CREATE TABLE chat_message (
  message_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  from_party uuid NOT NULL REFERENCES users(user_id),
  to_party   uuid NOT NULL REFERENCES users(user_id),
  by_person  uuid NOT NULL REFERENCES users(user_id),
  body       text NOT NULL,
  at         timestamptz NOT NULL DEFAULT clock_timestamp()
);

-- Email: a mailbox per person or entity; in the demo nothing is actually sent
CREATE TABLE mail_message (
  mail_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id  uuid NOT NULL REFERENCES users(user_id),
  folder    text NOT NULL CHECK (folder IN ('Inbox','Sent','Drafts')),
  from_addr text NOT NULL,
  to_addr   text NOT NULL,
  subject   text NOT NULL,
  body      text NOT NULL,
  work      text,              -- what the work band shows it became, if anything
  at        timestamptz NOT NULL DEFAULT clock_timestamp()
);

-- ---------- Krama Phase 4 ----------
-- krama.kind / krama.standalone and report.metric are defined in 01_schema.sql
CREATE TABLE module_member (
  module_id uuid NOT NULL REFERENCES krama(krama_id) ON DELETE CASCADE,
  member_id uuid NOT NULL REFERENCES krama(krama_id),
  PRIMARY KEY (module_id, member_id)
);
-- Reusable components: platform-made Stage, Topic or Question parts, named generically
CREATE TABLE component (
  component_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  level        text NOT NULL CHECK (level IN ('Stage','Topic','Question')),
  name         text NOT NULL UNIQUE,
  ownership    text NOT NULL DEFAULT 'Platform Built Platform Owned',
  description  text NOT NULL,
  body         jsonb NOT NULL      -- {topics:[{name, path, questions:[{text, flow_option, ask_in, rules}]}]} or {questions:[...]}
);

-- =====================================================================================
-- helpers
-- =====================================================================================
CREATE FUNCTION j(b jsonb, k text) RETURNS text LANGUAGE sql IMMUTABLE AS $$ SELECT NULLIF(trim(b->>k), '') $$;

CREATE FUNCTION need(actor uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF actor IS NULL THEN RAISE EXCEPTION 'Sign in first'; END IF; END $$;

CREATE FUNCTION need_admin(actor uuid, e uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM need(actor);
  IF NOT (is_entity_super(actor, e) OR is_super(actor)) THEN RAISE EXCEPTION 'Only an entity admin can do this'; END IF;
END $$;

CREATE FUNCTION need_member(actor uuid, e uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM need(actor);
  IF NOT (is_member_of_entity(actor, e) OR is_super(actor)) THEN RAISE EXCEPTION 'You are not connected to this entity'; END IF;
END $$;

-- The entity admin, or the admin of that Dept/BU
CREATE FUNCTION need_dept_rights(actor uuid, e uuid, d uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM need(actor);
  IF NOT (is_entity_super(actor, e) OR is_super(actor) OR (d IS NOT NULL AND admin_dept(actor, e) = d)) THEN
    RAISE EXCEPTION 'Only the entity admin or this Dept/BU''s admin can do this';
  END IF;
END $$;

CREATE FUNCTION free_domain(email text) RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  SELECT lower(split_part(email, '@', 2)) IN ('gmail.com','yahoo.com','outlook.com','hotmail.com','icloud.com','rediffmail.com','proton.me','live.com')
$$;

CREATE FUNCTION valid_email(email text) RETURNS boolean LANGUAGE sql IMMUTABLE AS $$ SELECT email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' $$;

-- A code is valid once, for its target and purpose
CREATE FUNCTION otp_ok(p_target text, p_purpose text, p_code text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE o record;
BEGIN
  SELECT * INTO o FROM otp_code WHERE lower(target) = lower(p_target) AND purpose = p_purpose AND NOT used ORDER BY at DESC LIMIT 1;
  IF o IS NULL OR o.code <> coalesce(trim(p_code), '') THEN RAISE EXCEPTION 'That code is not right. Request a new one.'; END IF;
  UPDATE otp_code SET used = true WHERE otp_id = o.otp_id;
END $$;

-- =====================================================================================
-- Create User and sign in (Access): no passwords anywhere
-- =====================================================================================
CREATE FUNCTION api_request_code(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
DECLARE c text := lpad((floor(random() * 1000000))::int::text, 6, '0'); t text := j(b, 'target'); p text := j(b, 'purpose');
BEGIN
  IF t IS NULL THEN RAISE EXCEPTION 'Enter where to send the code'; END IF;
  IF p IN ('access','signin','create_user_email','create_entity_personal') AND NOT valid_email(t) THEN RAISE EXCEPTION 'Enter a valid email'; END IF;
  IF p = 'signin' AND NOT EXISTS (SELECT 1 FROM users WHERE lower(personal_email) = lower(t) AND user_type = 'Individual') THEN
    RAISE EXCEPTION 'No Compane account uses that email. Create one instead.';
  END IF;
  IF p = 'create_user_email' AND EXISTS (SELECT 1 FROM users WHERE lower(personal_email) = lower(t)) THEN
    RAISE EXCEPTION 'That email already has an account. Sign in instead.';
  END IF;
  IF p IN ('work_email','join_work','invite_sender','connect_inviter','connect_accept','business_model') AND NOT valid_email(t) THEN RAISE EXCEPTION 'Enter a valid work email'; END IF;
  IF p IN ('work_email','join_work') AND free_domain(t) THEN RAISE EXCEPTION 'A work email must be on a business domain, not a free provider'; END IF;
  INSERT INTO otp_code (target, purpose, code) VALUES (t, p, c);
  RETURN json_build_object('sent', true, 'demo_code', c);
END $$;

CREATE FUNCTION api_sign_in(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
DECLARE u record;
BEGIN
  PERFORM otp_ok(j(b, 'email'), 'signin', j(b, 'code'));
  SELECT * INTO u FROM users WHERE lower(personal_email) = lower(j(b, 'email'));
  RETURN json_build_object('user_id', u.user_id, 'name', u.name);
END $$;

-- Access: one door for signing in and creating an account. The code proves the email; then either the
-- person is in, or (new email) a short-lived proof lets them finish creating the account.
CREATE FUNCTION api_access(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
DECLARE u record; tok text;
BEGIN
  PERFORM otp_ok(j(b, 'email'), 'access', j(b, 'code'));
  SELECT * INTO u FROM users WHERE lower(personal_email) = lower(j(b, 'email')) AND user_type = 'Individual';
  IF u.user_id IS NOT NULL THEN RETURN json_build_object('user_id', u.user_id, 'name', u.name); END IF;
  IF free_domain(j(b, 'email')) IS NOT TRUE THEN
    RAISE EXCEPTION 'A Yousr account uses your personal email (Gmail, Outlook and similar). Work emails come later, inside an entity.';
  END IF;
  tok := md5(random()::text || clock_timestamp()::text);
  INSERT INTO otp_code (target, purpose, code) VALUES (lower(j(b, 'email')), 'verified_email', tok);
  RETURN json_build_object('new', true, 'token', tok);
END $$;

CREATE FUNCTION api_create_user(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
DECLARE uid uuid; cid text;
BEGIN
  IF j(b, 'name') IS NULL THEN RAISE EXCEPTION 'Enter your name'; END IF;
  IF free_domain(j(b, 'email')) IS NOT TRUE THEN RAISE EXCEPTION 'Use a personal email (Gmail, Outlook and similar). Work emails come later, inside an entity.'; END IF;
  IF j(b, 'token') IS NOT NULL THEN PERFORM otp_ok(lower(j(b, 'email')), 'verified_email', j(b, 'token'));
  ELSE PERFORM otp_ok(j(b, 'email'), 'create_user_email', j(b, 'email_code')); END IF;
  IF EXISTS (SELECT 1 FROM users WHERE lower(personal_email) = lower(j(b, 'email'))) THEN RAISE EXCEPTION 'That email already has an account. Sign in instead.'; END IF;
  IF j(b, 'mobile') IS NULL THEN RAISE EXCEPTION 'Enter your mobile'; END IF;
  PERFORM otp_ok(j(b, 'mobile'), 'mobile', j(b, 'mobile_code'));
  cid := 'CMP-' || upper(substr(md5(random()::text), 1, 6));
  INSERT INTO users (name, personal_email, mobile, compane_id) VALUES (j(b, 'name'), lower(j(b, 'email')), j(b, 'mobile'), cid) RETURNING user_id INTO uid;
  INSERT INTO personal_document (owner_id, kind) VALUES (uid, 'National ID'), (uid, 'Tax ID'), (uid, 'Passport');
  RETURN json_build_object('user_id', uid, 'compane_id', cid);
END $$;

-- =====================================================================================
-- Create Entity: five steps, then setup and Complete setup
-- =====================================================================================
CREATE FUNCTION api_entity_name_free(actor uuid, b jsonb) RETURNS json LANGUAGE sql STABLE AS $$
  SELECT json_build_object('free', NOT EXISTS (SELECT 1 FROM users WHERE user_type = 'Company' AND lower(name) = lower(j(b, 'name'))))
$$;

CREATE FUNCTION api_create_entity(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
DECLARE e uuid; ct uuid; owner record;
BEGIN
  PERFORM need(actor);
  SELECT * INTO owner FROM users WHERE user_id = actor;
  IF j(b, 'country') IS NULL THEN RAISE EXCEPTION 'Step 1: pick the country'; END IF;
  SELECT company_type_id INTO ct FROM company_type WHERE sub_type = j(b, 'legal_type');
  IF ct IS NULL THEN RAISE EXCEPTION 'Step 2: pick the legal type'; END IF;
  IF j(b, 'name') IS NULL THEN RAISE EXCEPTION 'Step 3: enter the entity name'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE user_type = 'Company' AND lower(name) = lower(j(b, 'name'))) THEN RAISE EXCEPTION 'Step 3: that entity name is taken'; END IF;
  IF free_domain(j(b, 'work_email')) THEN RAISE EXCEPTION 'Step 4: the work email must be on a business domain'; END IF;
  IF EXISTS (SELECT 1 FROM person_entity_link WHERE lower(work_email) = lower(j(b, 'work_email'))) THEN RAISE EXCEPTION 'Step 4: that work email is already in use'; END IF;
  PERFORM otp_ok(j(b, 'work_email'), 'work_email', j(b, 'work_code'));
  IF lower(j(b, 'personal_email')) IS DISTINCT FROM lower(owner.personal_email) THEN RAISE EXCEPTION 'Step 5: use your own personal email'; END IF;
  PERFORM otp_ok(j(b, 'personal_email'), 'create_entity_personal', j(b, 'personal_code'));
  INSERT INTO users (name, user_type) VALUES (j(b, 'name'), 'Company') RETURNING user_id INTO e;
  INSERT INTO company (user_id, company_type_id, country, work_email, admin_personal_email) VALUES (e, ct, j(b, 'country'), lower(j(b, 'work_email')), lower(j(b, 'personal_email')));
  INSERT INTO person_entity_link (person_id, company_user_id, is_entity_super_user, work_email, sits, is_full_time, employer_approved)
  VALUES (actor, e, true, lower(j(b, 'work_email')), 'Admin above Dept/BU head', false, true);
  RETURN json_build_object('entity_id', e, 'name', j(b, 'name'));
END $$;

CREATE FUNCTION api_entity_setup(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
DECLARE e uuid := (b->>'entity_id')::uuid;
BEGIN
  PERFORM need_admin(actor, e);
  IF j(b, 'category') NOT IN ('Services','Trading','Manufacturing') THEN RAISE EXCEPTION 'Pick Services, Trading or Manufacturing'; END IF;
  IF j(b, 'sub_category') IS NULL THEN RAISE EXCEPTION 'Pick the sub-category'; END IF;
  IF j(b, 'size') NOT IN ('Micro','Small','Medium','Large') THEN RAISE EXCEPTION 'Pick the size'; END IF;
  IF j(b, 'business_model') NOT IN ('Functional','Business Unit') THEN RAISE EXCEPTION 'Pick Function based or Business Unit based'; END IF;
  UPDATE company SET category = j(b, 'category'), sub_category = j(b, 'sub_category'), size = j(b, 'size'),
         business_model = j(b, 'business_model'), corporate_doc = j(b, 'corporate_doc') WHERE user_id = e;
  RETURN json_build_object('ok', true);
END $$;

CREATE FUNCTION api_complete_setup(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
DECLARE e uuid := (b->>'entity_id')::uuid; item text := j(b, 'item');
BEGIN
  PERFORM need_admin(actor, e);
  IF item NOT IN ('Public pill','Work email','Catalogue','Your team') THEN RAISE EXCEPTION 'Unknown setup item'; END IF;
  UPDATE company SET complete_setup = jsonb_set(complete_setup, ARRAY[item],
         jsonb_build_object('state', COALESCE(j(b, 'state'), 'Done'), 'assigned_to', j(b, 'assigned_to')), true) WHERE user_id = e;
  RETURN json_build_object('ok', true);
END $$;

-- =====================================================================================
-- Connect User Entity: one flow, the admin's invite and the person joining
-- =====================================================================================
CREATE FUNCTION api_invite(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
DECLARE e uuid := (b->>'entity_id')::uuid; sender text;
BEGIN
  PERFORM need_admin(actor, e);
  IF j(b, 'work_email') IS NULL OR free_domain(j(b, 'work_email')) THEN RAISE EXCEPTION 'Enter their work email on a business domain'; END IF;
  IF j(b, 'name') IS NULL THEN RAISE EXCEPTION 'Enter their name'; END IF;
  IF j(b, 'sits') NOT IN ('Admin above Dept/BU head','Dept/BU head or below') THEN RAISE EXCEPTION 'Where do they sit?'; END IF;
  IF EXISTS (SELECT 1 FROM person_entity_link WHERE company_user_id = e AND lower(work_email) = lower(j(b, 'work_email')))
     OR EXISTS (SELECT 1 FROM entity_invite WHERE entity_id = e AND lower(work_email) = lower(j(b, 'work_email')) AND status = 'Pending') THEN
    RAISE EXCEPTION 'One work email is one member of an entity; this one is already used';
  END IF;
  SELECT work_email INTO sender FROM person_entity_link WHERE person_id = actor AND company_user_id = e;
  PERFORM otp_ok(sender, 'invite_sender', j(b, 'sender_code'));
  INSERT INTO entity_invite (entity_id, work_email, name, mobile, designation, dept_bu_id, sits, sent_by)
  VALUES (e, lower(j(b, 'work_email')), j(b, 'name'), j(b, 'mobile'), j(b, 'designation'), NULLIF(b->>'dept_bu_id', '')::uuid, j(b, 'sits'), actor);
  RETURN json_build_object('ok', true);
END $$;

CREATE FUNCTION api_invite_action(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
DECLARE i record;
BEGIN
  SELECT * INTO i FROM entity_invite WHERE invite_id = (b->>'invite_id')::uuid;
  IF i IS NULL THEN RAISE EXCEPTION 'Invite not found'; END IF;
  IF j(b, 'action') = 'cancel' THEN PERFORM need_admin(actor, i.entity_id); UPDATE entity_invite SET status = 'Cancelled' WHERE invite_id = i.invite_id;
  ELSIF j(b, 'action') = 'resend' THEN PERFORM need_admin(actor, i.entity_id); UPDATE entity_invite SET status = 'Pending', at = clock_timestamp() WHERE invite_id = i.invite_id;
  ELSIF j(b, 'action') = 'decline' THEN PERFORM need(actor); UPDATE entity_invite SET status = 'Declined' WHERE invite_id = i.invite_id;
  ELSE RAISE EXCEPTION 'Unknown action'; END IF;
  RETURN json_build_object('ok', true);
END $$;

-- The invited person, signed in, joins with the code sent to their work email: the single gate
CREATE FUNCTION api_join_entity(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
DECLARE i record;
BEGIN
  PERFORM need(actor);
  SELECT * INTO i FROM entity_invite WHERE invite_id = (b->>'invite_id')::uuid AND status = 'Pending';
  IF i IS NULL THEN RAISE EXCEPTION 'This invite is no longer open'; END IF;
  PERFORM otp_ok(i.work_email, 'join_work', j(b, 'code'));
  INSERT INTO person_entity_link (person_id, company_user_id, dept_bu_id, is_entity_super_user, work_email, designation, sits, is_full_time, employer_approved)
  VALUES (actor, i.entity_id, i.dept_bu_id, i.sits = 'Admin above Dept/BU head', i.work_email, i.designation, i.sits, false, true)
  ON CONFLICT (person_id, company_user_id) DO NOTHING;
  UPDATE entity_invite SET status = 'Accepted' WHERE invite_id = i.invite_id;
  RETURN json_build_object('entity_id', i.entity_id);
END $$;

-- Invites waiting for the signed-in person: matched by the work emails they say are theirs, shown in their Yousr space
CREATE FUNCTION api_my_invites(actor uuid, b jsonb) RETURNS json LANGUAGE sql STABLE AS $$
  SELECT COALESCE(json_agg(json_build_object('invite_id', i.invite_id, 'entity', user_name(i.entity_id), 'work_email', i.work_email,
           'name', i.name, 'designation', i.designation, 'from', user_name(i.sent_by)) ORDER BY i.at DESC), '[]')
    FROM entity_invite i WHERE i.status = 'Pending' AND (lower(i.name) = lower((SELECT name FROM users WHERE user_id = actor))
                                                      OR lower(i.work_email) = lower(j(b, 'work_email')))
$$;

-- =====================================================================================
-- Connect Entity Entity: seven steps, one activation gate (the counterparty's code)
-- =====================================================================================
CREATE FUNCTION api_connections(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql STABLE AS $$
DECLARE e uuid := (b->>'entity_id')::uuid;
BEGIN
  PERFORM need_module(actor, e, 'Connections');
  RETURN (SELECT COALESCE(json_agg(json_build_object('connection_id', c.connection_id,
            'other', CASE WHEN c.from_entity = e THEN c.to_name ELSE user_name(c.from_entity) END,
            'relationship', CASE WHEN c.from_entity = e THEN c.relationship
                                 ELSE CASE c.relationship WHEN 'Vendor' THEN 'Client' WHEN 'Pre-vendor' THEN 'Pre-client' WHEN 'Client' THEN 'Vendor' ELSE 'Pre-vendor' END END,
            'state', c.state, 'failure', c.failure, 'resent', c.resent, 'mine', c.from_entity = e,
            'can_accept', c.to_entity = e AND c.state = 'Pending' AND c.failure IS NULL) ORDER BY c.at DESC), '[]')
    FROM entity_connection c WHERE c.from_entity = e OR c.to_entity = e);
END $$;

-- Steps 1–4: search, identify, the inviter's code authorises, both placeholders are created Pending
CREATE FUNCTION api_connect_invite(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
DECLARE e uuid := (b->>'entity_id')::uuid; t uuid := NULLIF(b->>'to_entity', '')::uuid; sender text;
BEGIN
  PERFORM need_admin(actor, e);
  IF j(b, 'relationship') NOT IN ('Pre-client','Client','Pre-vendor','Vendor') THEN RAISE EXCEPTION 'Pick the relationship'; END IF;
  IF t IS NULL AND j(b, 'to_name') IS NULL THEN RAISE EXCEPTION 'Find the entity, or enter its name'; END IF;
  IF t = e THEN RAISE EXCEPTION 'An entity cannot connect to itself'; END IF;
  IF t IS NOT NULL AND EXISTS (SELECT 1 FROM entity_connection WHERE ((from_entity = e AND to_entity = t) OR (from_entity = t AND to_entity = e)) AND failure IS NULL) THEN
    RAISE EXCEPTION 'These two entities already have a connection';
  END IF;
  SELECT work_email INTO sender FROM person_entity_link WHERE person_id = actor AND company_user_id = e;
  PERFORM otp_ok(sender, 'connect_inviter', j(b, 'code'));
  INSERT INTO entity_connection (from_entity, to_entity, to_name, relationship, state, invited_by)
  VALUES (e, t, COALESCE(user_name(t), j(b, 'to_name')), j(b, 'relationship'), CASE WHEN t IS NULL THEN 'Standalone' ELSE 'Pending' END, actor);
  RETURN json_build_object('ok', true, 'on_platform', t IS NOT NULL);
END $$;

-- Step 6: the counterparty validates with its own work-email code: the single activation gate
CREATE FUNCTION api_connect_accept(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
DECLARE c record; mine text;
BEGIN
  SELECT * INTO c FROM entity_connection WHERE connection_id = (b->>'connection_id')::uuid;
  IF c IS NULL OR c.state <> 'Pending' OR c.failure IS NOT NULL THEN RAISE EXCEPTION 'This connection is not waiting for you'; END IF;
  PERFORM need_admin(actor, c.to_entity);
  SELECT work_email INTO mine FROM person_entity_link WHERE person_id = actor AND company_user_id = c.to_entity;
  PERFORM otp_ok(mine, 'connect_accept', j(b, 'code'));
  UPDATE entity_connection SET state = 'Connected' WHERE connection_id = c.connection_id;
  RETURN json_build_object('ok', true);
END $$;

CREATE FUNCTION api_connect_action(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
DECLARE c record;
BEGIN
  SELECT * INTO c FROM entity_connection WHERE connection_id = (b->>'connection_id')::uuid;
  PERFORM need_admin(actor, c.from_entity);
  IF j(b, 'action') = 'cancel' THEN UPDATE entity_connection SET failure = 'Cancelled' WHERE connection_id = c.connection_id;
  ELSIF j(b, 'action') = 'expire' THEN UPDATE entity_connection SET failure = 'Expired' WHERE connection_id = c.connection_id;
  ELSIF j(b, 'action') = 'resend' THEN
    IF c.resent >= 5 THEN RAISE EXCEPTION 'Resent 5 times already; it needs manual follow-up'; END IF;
    UPDATE entity_connection SET failure = NULL, resent = resent + 1, at = clock_timestamp() WHERE connection_id = c.connection_id;
  ELSIF j(b, 'action') = 'disconnect' THEN UPDATE entity_connection SET state = 'Standalone', failure = NULL WHERE connection_id = c.connection_id;
  ELSE RAISE EXCEPTION 'Unknown action'; END IF;
  RETURN json_build_object('ok', true);
END $$;

-- =====================================================================================
-- Settings
-- =====================================================================================
CREATE FUNCTION api_settings(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql STABLE AS $$
DECLARE e uuid := (b->>'entity_id')::uuid; c record;
BEGIN
  PERFORM need_member(actor, e);
  SELECT co.*, ct.sub_type, u.name INTO c FROM company co JOIN company_type ct USING (company_type_id) JOIN users u ON u.user_id = co.user_id WHERE co.user_id = e;
  RETURN json_build_object(
    'is_admin', is_entity_super(actor, e) OR is_super(actor),
    'entity', json_build_object('name', c.name, 'country', c.country, 'legal_type', c.sub_type, 'authorised_email', c.authorised_email,
               'mobile', c.entity_mobile, 'business_model', COALESCE(c.business_model, 'Functional'), 'category', c.category,
               'sub_category', c.sub_category, 'size', c.size, 'work_email', c.work_email, 'complete_setup', c.complete_setup),
    'dept_bus', (SELECT COALESCE(json_agg(json_build_object('dept_bu_id', d.dept_bu_id, 'name', d.name,
        'grades', (SELECT COALESCE(json_agg(json_build_object('grade_id', g.grade_id, 'name', g.name, 'rank', g.rank) ORDER BY g.rank), '[]') FROM grade g WHERE g.dept_bu_id = d.dept_bu_id),
        'designations', (SELECT COALESCE(json_agg(json_build_object('name', ds.name, 'grade', (SELECT name FROM grade WHERE grade_id = ds.grade_id)) ORDER BY ds.name), '[]') FROM designation ds WHERE ds.dept_bu_id = d.dept_bu_id),
        'personas', (SELECT COALESCE(json_agg(json_build_object('persona_id', p.persona_id, 'name', p.name, 'grade', (SELECT name FROM grade WHERE grade_id = p.grade_id),
                      'reports_to', (SELECT name FROM work_persona r WHERE r.persona_id = p.reports_to), 'exception', p.is_exception, 'modules', p.modules,
                      'actions', p.actions) ORDER BY p.name), '[]')
                     FROM work_persona p WHERE p.dept_bu_id = d.dept_bu_id)) ORDER BY d.name), '[]') FROM dept_bu d WHERE d.company_user_id = e),
    'exceptions', (SELECT COALESCE(json_agg(json_build_object('persona_id', p.persona_id, 'name', p.name, 'reports_to', (SELECT name FROM work_persona r WHERE r.persona_id = p.reports_to))), '[]')
                   FROM work_persona p WHERE p.entity_id = e AND p.dept_bu_id IS NULL),
    'users', (SELECT COALESCE(json_agg(json_build_object('link_id', l.link_id, 'name', user_name(l.person_id), 'work_email', l.work_email, 'designation', l.designation,
                'dept_bu', (SELECT name FROM dept_bu WHERE dept_bu_id = l.dept_bu_id), 'dept_bu_id', l.dept_bu_id, 'admin', l.is_entity_super_user,
                'persona', (SELECT name FROM work_persona WHERE persona_id = l.persona_id), 'persona_id', l.persona_id) ORDER BY user_name(l.person_id)), '[]')
              FROM person_entity_link l WHERE l.company_user_id = e),
    'invites', (SELECT COALESCE(json_agg(json_build_object('invite_id', i.invite_id, 'name', i.name, 'work_email', i.work_email, 'status', i.status, 'sits', i.sits) ORDER BY i.at DESC), '[]')
                FROM entity_invite i WHERE i.entity_id = e),
    'connection_hub', c.connection_hub,
    'ui', json_build_object('variant', COALESCE(c.size, 'Small') || ' · ' || COALESCE(c.business_model, 'Functional'),
                            'brand', 'compane'),
    'plan', json_build_object('plan', CASE COALESCE(c.size, 'Small') WHEN 'Micro' THEN 'Starter' WHEN 'Small' THEN 'Growth' ELSE 'Scale' END,
                              'seats_used', (SELECT count(*) FROM person_entity_link WHERE company_user_id = e),
                              'seats', CASE COALESCE(c.size, 'Small') WHEN 'Micro' THEN 5 WHEN 'Small' THEN 25 WHEN 'Medium' THEN 100 ELSE 500 END,
                              'ai_questions_this_month', (SELECT count(*) FROM audit_log a JOIN run r USING (run_id) WHERE r.company_user_id = e)),
    'delete_requested_at', c.delete_requested_at,
    'delete_on', (c.delete_requested_at + interval '30 days')::date);
END $$;

CREATE FUNCTION api_save_entity_details(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
DECLARE e uuid := (b->>'entity_id')::uuid;
BEGIN
  PERFORM need_admin(actor, e);
  IF j(b, 'authorised_email') IS NOT NULL AND NOT valid_email(j(b, 'authorised_email')) THEN RAISE EXCEPTION 'Enter a valid authorised email'; END IF;
  UPDATE company SET authorised_email = j(b, 'authorised_email'), entity_mobile = j(b, 'mobile') WHERE user_id = e;
  RETURN json_build_object('ok', true);
END $$;

-- Changing the Business Model is a structural change: confirmed by a code to the admin's work email
CREATE FUNCTION api_change_business_model(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
DECLARE e uuid := (b->>'entity_id')::uuid; mine text;
BEGIN
  PERFORM need_admin(actor, e);
  IF j(b, 'model') NOT IN ('Functional','Business Unit') THEN RAISE EXCEPTION 'Pick Function based or Business Unit based'; END IF;
  SELECT work_email INTO mine FROM person_entity_link WHERE person_id = actor AND company_user_id = e;
  PERFORM otp_ok(mine, 'business_model', j(b, 'code'));
  UPDATE company SET business_model = j(b, 'model') WHERE user_id = e;
  RETURN json_build_object('ok', true);
END $$;

CREATE FUNCTION api_add_org(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
DECLARE e uuid := (b->>'entity_id')::uuid; d uuid := NULLIF(b->>'dept_bu_id', '')::uuid; k text := j(b, 'kind'); n text := j(b, 'name'); g uuid;
BEGIN
  IF k = 'Dept/BU' THEN PERFORM need_admin(actor, e); ELSE PERFORM need_dept_rights(actor, e, d); END IF;
  IF n IS NULL THEN RAISE EXCEPTION 'Enter a name'; END IF;
  IF d IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dept_bu WHERE dept_bu_id = d AND company_user_id = e) THEN RAISE EXCEPTION 'That Dept/BU is not this entity''s'; END IF;
  IF k = 'Dept/BU' THEN
    INSERT INTO dept_bu (company_user_id, name) VALUES (e, n);
  ELSIF k = 'Grade' THEN
    INSERT INTO grade (dept_bu_id, name, rank) VALUES (d, n, COALESCE((SELECT max(rank) FROM grade WHERE dept_bu_id = d), 0) + 1);
  ELSIF k = 'Designation' THEN
    SELECT grade_id INTO g FROM grade WHERE dept_bu_id = d AND name = j(b, 'grade');
    INSERT INTO designation (dept_bu_id, grade_id, name) VALUES (d, g, n);
  ELSIF k = 'Work Persona' THEN
    SELECT grade_id INTO g FROM grade WHERE dept_bu_id = d AND name = j(b, 'grade');
    INSERT INTO work_persona (entity_id, dept_bu_id, grade_id, name, reports_to, is_exception, modules)
    VALUES (e, d, g, n, NULLIF(b->>'reports_to', '')::uuid, false,
            CASE WHEN (b->>'krama')::boolean THEN ARRAY['WOM','Krama'] ELSE ARRAY['WOM'] END);
  ELSIF k = 'Exception' THEN
    INSERT INTO work_persona (entity_id, dept_bu_id, name, reports_to, is_exception)
    VALUES (e, d, 'Exception · ' || n, NULLIF(b->>'reports_to', '')::uuid, true);
  ELSE RAISE EXCEPTION 'Unknown item'; END IF;
  RETURN json_build_object('ok', true);
END $$;

CREATE FUNCTION api_member_action(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
DECLARE l record;
BEGIN
  SELECT * INTO l FROM person_entity_link WHERE link_id = (b->>'link_id')::uuid;
  PERFORM need_admin(actor, l.company_user_id);
  IF j(b, 'action') = 'disconnect' THEN
    IF l.person_id = actor THEN RAISE EXCEPTION 'You cannot disconnect yourself'; END IF;
    DELETE FROM room_member WHERE person_id = l.person_id AND room_id IN (SELECT room_id FROM room rm JOIN run r USING (run_id) WHERE r.company_user_id = l.company_user_id);
    DELETE FROM person_entity_link WHERE link_id = l.link_id;
  ELSIF j(b, 'action') = 'edit' THEN
    UPDATE person_entity_link SET dept_bu_id = NULLIF(b->>'dept_bu_id', '')::uuid, designation = j(b, 'designation'),
           is_entity_super_user = COALESCE((b->>'admin')::boolean, false), persona_id = NULLIF(b->>'persona_id', '')::uuid WHERE link_id = l.link_id;
  ELSE RAISE EXCEPTION 'Unknown action'; END IF;
  RETURN json_build_object('ok', true);
END $$;

CREATE FUNCTION api_save_connection_hub(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
DECLARE e uuid := (b->>'entity_id')::uuid;
BEGIN
  PERFORM need_admin(actor, e);
  UPDATE company SET connection_hub = COALESCE(b->'hub', '{}'::jsonb) WHERE user_id = e;
  RETURN json_build_object('ok', true);
END $$;

CREATE FUNCTION api_entity_data(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
DECLARE e uuid := (b->>'entity_id')::uuid;
BEGIN
  PERFORM need_admin(actor, e);
  IF j(b, 'action') = 'delete' THEN UPDATE company SET delete_requested_at = clock_timestamp() WHERE user_id = e;
  ELSIF j(b, 'action') = 'cancel_delete' THEN UPDATE company SET delete_requested_at = NULL WHERE user_id = e;
  ELSIF j(b, 'action') = 'export' THEN
    RETURN json_build_object('entity', user_name(e), 'exported_at', now(),
      'catalogue', (SELECT json_agg(row_to_json(ci)) FROM catalogue_item ci WHERE ci.company_user_id = e),
      'runs', (SELECT json_agg(json_build_object('label', run_label(r), 'status', r.status, 'result', r.result, 'fy', r.fy)) FROM run r WHERE r.company_user_id = e),
      'people', (SELECT json_agg(json_build_object('name', user_name(person_id), 'work_email', work_email)) FROM person_entity_link WHERE company_user_id = e));
  ELSE RAISE EXCEPTION 'Unknown action'; END IF;
  RETURN json_build_object('ok', true);
END $$;

-- Personal settings: Profile is name and photo only
CREATE FUNCTION api_profile(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
BEGIN
  PERFORM need(actor);
  IF j(b, 'name') IS NOT NULL THEN UPDATE users SET name = j(b, 'name'), photo = j(b, 'photo') WHERE user_id = actor; END IF;
  RETURN (SELECT json_build_object('name', name, 'photo', photo, 'personal_email', personal_email, 'mobile', mobile, 'compane_id', compane_id)
            FROM users WHERE user_id = actor);
END $$;

-- =====================================================================================
-- My ID (personal): documents verified through DigiLocker only
-- =====================================================================================
CREATE FUNCTION api_my_id(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
BEGIN
  PERFORM need(actor);
  IF j(b, 'verify') IS NOT NULL THEN
    UPDATE personal_document SET status = 'Verified', at = clock_timestamp() WHERE doc_id = (b->>'verify')::uuid AND owner_id = actor;
    UPDATE users SET identity_verified = true WHERE user_id = actor;
  END IF;
  RETURN (SELECT json_build_object('compane_id', u.compane_id, 'verified', u.identity_verified,
           'documents', (SELECT COALESCE(json_agg(json_build_object('doc_id', d.doc_id, 'kind', d.kind, 'status', d.status,
                          'at', to_char(d.at AT TIME ZONE 'Asia/Kolkata', 'DD Mon YYYY')) ORDER BY d.kind), '[]') FROM personal_document d WHERE d.owner_id = actor))
            FROM users u WHERE u.user_id = actor);
END $$;

-- =====================================================================================
-- Files: every file in the space, by where it came from (attached in answers, or in a room registry)
-- =====================================================================================
CREATE FUNCTION api_files(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql STABLE AS $$
DECLARE e uuid := NULLIF(b->>'entity_id', '')::uuid;
BEGIN
  PERFORM need(actor);
  IF e IS NULL THEN
    RETURN (SELECT COALESCE(json_agg(json_build_object('file', d.kind, 'from', 'My ID', 'status', d.status)), '[]') FROM personal_document d WHERE d.owner_id = actor AND d.status = 'Verified');
  END IF;
  PERFORM need_member(actor, e);
  RETURN (SELECT COALESCE(json_agg(f ORDER BY f->>'file'), '[]') FROM (
    SELECT json_build_object('file', COALESCE(x.answer_data->>'file', x.answer_data->'attachment'->>'file'),
             'from', run_label(r) || ' · ' || q.text, 'room', rm.kind || ' · ' || rm.name,
             'mobility', COALESCE(x.answer_data->>'mobility', x.answer_data->'attachment'->>'mobility'), 'status', x.answer_state) f
      FROM question_run x JOIN question q USING (question_id) JOIN run r USING (run_id) JOIN room rm ON rm.room_id = x.room_id
     WHERE COALESCE(x.answer_data->>'file', x.answer_data->'attachment'->>'file') IS NOT NULL
       AND (r.company_user_id = e OR r.counterparty = e) AND can_see_qr(x.qr_id, actor)
    UNION ALL
    SELECT json_build_object('file', re.title, 'from', run_label(r) || ' · registry ' || g.name, 'room', rm.kind || ' · ' || rm.name, 'mobility', NULL, 'status', re.status)
      FROM registry_entry re JOIN registry g USING (registry_id) JOIN room rm ON rm.room_id = g.room_id JOIN run r ON r.run_id = rm.run_id
     WHERE re.kind = 'File' AND (r.company_user_id = e OR r.counterparty = e) AND room_open_to(rm.room_id, actor)) z);
END $$;

-- =====================================================================================
-- Chat: entity first; conversations between this space and a connected entity or a person
-- =====================================================================================
CREATE FUNCTION api_chat(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
DECLARE me uuid := COALESCE(NULLIF(b->>'entity_id', '')::uuid, actor); other uuid := NULLIF(b->>'with', '')::uuid;
BEGIN
  PERFORM need(actor);
  IF me <> actor THEN PERFORM need_member(actor, me); END IF;
  IF j(b, 'body') IS NOT NULL AND other IS NOT NULL THEN
    INSERT INTO chat_message (from_party, to_party, by_person, body) VALUES (me, other, actor, j(b, 'body'));
  END IF;
  RETURN json_build_object(
    'contacts', (SELECT COALESCE(json_agg(json_build_object('user_id', c.id, 'name', user_name(c.id), 'kind', user_type_of(c.id)) ORDER BY user_type_of(c.id), user_name(c.id)), '[]') FROM (
        SELECT CASE WHEN from_entity = me THEN to_entity ELSE from_entity END AS id FROM entity_connection
         WHERE (from_entity = me OR to_entity = me) AND state = 'Connected' AND to_entity IS NOT NULL
        UNION
        SELECT l2.person_id FROM person_entity_link l2 WHERE l2.company_user_id = me AND l2.person_id <> actor
        UNION
        SELECT CASE WHEN from_party = me THEN to_party ELSE from_party END FROM chat_message WHERE from_party = me OR to_party = me) c WHERE c.id IS NOT NULL),
    'messages', (SELECT COALESCE(json_agg(json_build_object('mine', from_party = me, 'by', user_name(by_person), 'body', body,
                   'at', to_char(at AT TIME ZONE 'Asia/Kolkata', 'DD Mon HH24:MI')) ORDER BY at), '[]')
                 FROM chat_message WHERE other IS NOT NULL AND ((from_party = me AND to_party = other) OR (from_party = other AND to_party = me))));
END $$;

-- =====================================================================================
-- Email: a mailbox per space. Work band shows what an email became. Nothing is really sent in the demo.
-- =====================================================================================
CREATE FUNCTION api_email(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
DECLARE me uuid := COALESCE(NULLIF(b->>'entity_id', '')::uuid, actor); addr text;
BEGIN
  PERFORM need(actor);
  IF me <> actor THEN PERFORM need_member(actor, me); END IF;
  addr := CASE WHEN me = actor THEN (SELECT personal_email FROM users WHERE user_id = actor)
               ELSE (SELECT work_email FROM person_entity_link WHERE person_id = actor AND company_user_id = me) END;
  IF j(b, 'to') IS NOT NULL THEN
    IF NOT valid_email(j(b, 'to')) THEN RAISE EXCEPTION 'Enter a valid address'; END IF;
    IF j(b, 'subject') IS NULL OR j(b, 'body') IS NULL THEN RAISE EXCEPTION 'An email needs a subject and a body'; END IF;
    INSERT INTO mail_message (owner_id, folder, from_addr, to_addr, subject, body) VALUES (me, COALESCE(j(b, 'folder'), 'Sent'), COALESCE(addr, 'you'), j(b, 'to'), j(b, 'subject'), j(b, 'body'));
  END IF;
  RETURN json_build_object('address', addr,
    'mails', (SELECT COALESCE(json_agg(json_build_object('mail_id', m.mail_id, 'folder', m.folder, 'from', m.from_addr, 'to', m.to_addr, 'subject', m.subject,
               'body', m.body, 'work', m.work, 'at', to_char(m.at AT TIME ZONE 'Asia/Kolkata', 'DD Mon HH24:MI')) ORDER BY m.at DESC), '[]')
              FROM mail_message m WHERE m.owner_id = me));
END $$;

-- =====================================================================================
-- Search: only the current space, never across spaces
-- =====================================================================================
CREATE FUNCTION api_search(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql STABLE AS $$
DECLARE e uuid := NULLIF(b->>'entity_id', '')::uuid; q text := '%' || lower(coalesce(j(b, 'q'), '')) || '%';
BEGIN
  PERFORM need(actor);
  IF e IS NULL THEN
    RETURN (SELECT COALESCE(json_agg(z), '[]') FROM (
      SELECT json_build_object('kind', 'Personal task', 'title', title, 'sub', status) z FROM personal_task WHERE owner_id = actor AND lower(title) LIKE q
      UNION ALL SELECT json_build_object('kind', 'Document', 'title', kind, 'sub', status) FROM personal_document WHERE owner_id = actor AND lower(kind) LIKE q) s);
  END IF;
  PERFORM need_member(actor, e);
  RETURN (SELECT COALESCE(json_agg(z), '[]') FROM (
    SELECT json_build_object('kind', 'Catalogue item', 'title', name, 'sub', COALESCE(catalogue_code, ''), 'item_id', item_id) z FROM catalogue_item WHERE company_user_id = e AND lower(name) LIKE q
    UNION ALL SELECT json_build_object('kind', 'Task', 'title', ci.name || ' · ' || run_label(r), 'sub', r.status, 'run_id', r.run_id)
      FROM run r JOIN catalogue_item ci USING (item_id) WHERE (r.company_user_id = e OR r.counterparty = e) AND r.run_id IN (SELECT visible_runs(actor))
       AND (lower(ci.name) LIKE q OR lower(r.instance_code) LIKE q)
    UNION ALL SELECT json_build_object('kind', 'Question', 'title', q2.text, 'sub', run_label(r) || ' · ' || x.answer_state, 'run_id', r.run_id, 'qr_id', x.qr_id)
      FROM question_run x JOIN question q2 USING (question_id) JOIN run r USING (run_id)
     WHERE (r.company_user_id = e OR r.counterparty = e) AND lower(q2.text) LIKE q AND can_see_qr(x.qr_id, actor)
    UNION ALL SELECT json_build_object('kind', 'Person', 'title', user_name(person_id), 'sub', COALESCE(designation, '')) FROM person_entity_link WHERE company_user_id = e AND lower(user_name(person_id)) LIKE q
    UNION ALL SELECT json_build_object('kind', 'Krama', 'title', name || ' v' || version, 'sub', status) FROM krama WHERE owner_entity = e AND lower(name) LIKE q) s);
END $$;

-- =====================================================================================
-- Revenue (sell side), Compliance, Tools, Discover and Connect
-- =====================================================================================
CREATE FUNCTION api_revenue(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql STABLE AS $$
DECLARE e uuid := (b->>'entity_id')::uuid;
BEGIN
  PERFORM need_module(actor, e, 'Revenue');
  RETURN json_build_object(
    'sell', (SELECT COALESCE(json_agg(json_build_object('run_id', r.run_id, 'label', run_label(r), 'item', ci.name, 'client', user_name(r.counterparty),
               'relationship', r.relationship, 'status', r.status, 'result', r.result,
               'price', (SELECT sum(est_price) FROM estimate_line WHERE run_id = r.run_id), 'cost', (SELECT sum(est_cost) FROM estimate_line WHERE run_id = r.run_id)) ORDER BY r.instance_code), '[]')
             FROM run r JOIN catalogue_item ci USING (item_id) WHERE r.company_user_id = e AND r.relationship IN ('Client','Pre-client')),
    'buy_for_others', (SELECT COALESCE(json_agg(json_build_object('run_id', r.run_id, 'label', run_label(r), 'item', ci.name, 'client', user_name(r.company_user_id), 'status', r.status) ORDER BY r.instance_code), '[]')
             FROM run r JOIN catalogue_item ci USING (item_id) WHERE r.counterparty = e AND r.relationship IN ('Vendor','Pre-vendor')));
END $$;

CREATE FUNCTION api_compliance(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql STABLE AS $$
DECLARE e uuid := (b->>'entity_id')::uuid;
BEGIN
  PERFORM need_module(actor, e, 'Compliance');
  RETURN (SELECT COALESCE(json_agg(json_build_object('item_id', ci.item_id, 'name', ci.name,
            'domain', (SELECT d.name FROM domain_persona p JOIN catalogue_domain d USING (domain_id) WHERE p.domain_persona_id = ci.domain_persona_id),
            'persona', (SELECT p.name FROM domain_persona p WHERE p.domain_persona_id = ci.domain_persona_id),
            'runs', (SELECT COALESCE(json_agg(json_build_object('run_id', r.run_id, 'label', run_label(r), 'status', r.status, 'result', r.result, 'fy', r.fy)), '[]') FROM run r WHERE r.item_id = ci.item_id))), '[]')
            FROM catalogue_item ci WHERE ci.company_user_id = e AND ci.catalogue = 'Compliance');
END $$;

CREATE FUNCTION api_discover(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql STABLE AS $$
DECLARE e uuid := NULLIF(b->>'entity_id', '')::uuid; q text := '%' || lower(coalesce(j(b, 'q'), '')) || '%';
BEGIN
  PERFORM need(actor);
  RETURN (SELECT COALESCE(json_agg(json_build_object('entity_id', u.user_id, 'name', u.name, 'persona', pt.display_name,
            'connection', (SELECT state FROM entity_connection c WHERE e IS NOT NULL AND ((c.from_entity = e AND c.to_entity = u.user_id) OR (c.from_entity = u.user_id AND c.to_entity = e)) AND failure IS NULL LIMIT 1),
            'items', (SELECT COALESCE(json_agg(json_build_object('name', ci.name, 'type', ci.item_type)), '[]')
                        FROM catalogue_item ci WHERE ci.company_user_id = u.user_id AND ci.visibility_audience = 'Discover and Connect'))
            ORDER BY u.name), '[]')
            FROM users u JOIN company co ON co.user_id = u.user_id LEFT JOIN persona_type pt ON pt.persona_type_id = co.persona_type_id
           WHERE u.user_type = 'Company' AND u.user_id IS DISTINCT FROM e AND (lower(u.name) LIKE q OR lower(coalesce(pt.display_name, '')) LIKE q));
END $$;

-- =====================================================================================
-- Krama Phase 4
-- =====================================================================================
-- Report answers come from live data each time they are opened
CREATE FUNCTION report_answer(p_metric text, e uuid) RETURNS json LANGUAGE sql STABLE AS $$
  SELECT CASE p_metric
    WHEN 'runs_by_status' THEN (SELECT json_agg(json_build_object('label', COALESCE(result, status), 'value', n)) FROM (
         SELECT status, result, count(*) n FROM run WHERE company_user_id = e OR counterparty = e GROUP BY status, result) s)
    WHEN 'questions_by_state' THEN (SELECT json_agg(json_build_object('label', answer_state, 'value', n)) FROM (
         SELECT x.answer_state, count(*) n FROM question_run x JOIN run r USING (run_id) WHERE r.company_user_id = e OR r.counterparty = e GROUP BY x.answer_state) s)
    WHEN 'overdue_questions' THEN (SELECT json_agg(json_build_object('label', run_label(r) || ' · ' || q.text, 'value', current_date - x.due_date))
         FROM question_run x JOIN question q USING (question_id) JOIN run r USING (run_id)
        WHERE (r.company_user_id = e OR r.counterparty = e) AND x.status = 'Open' AND x.due_date < current_date)
    WHEN 'runs_by_item' THEN (SELECT json_agg(json_build_object('label', name, 'value', n)) FROM (
         SELECT ci.name, count(*) n FROM run r JOIN catalogue_item ci USING (item_id) WHERE r.company_user_id = e GROUP BY ci.name) s)
    WHEN 'estimate_totals' THEN (SELECT json_agg(json_build_object('label', lbl, 'value', v)) FROM (
         SELECT 'Estimated price' lbl, sum(est_price) v FROM estimate_line l JOIN run r USING (run_id) WHERE r.company_user_id = e
         UNION ALL SELECT 'Estimated cost', sum(est_cost) FROM estimate_line l JOIN run r USING (run_id) WHERE r.company_user_id = e
         UNION ALL SELECT 'Actual price', sum(act_price) FROM estimate_line l JOIN run r USING (run_id) WHERE r.company_user_id = e) s)
  END
$$;

CREATE FUNCTION api_reports(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql STABLE AS $$
DECLARE e uuid := (b->>'entity_id')::uuid;
BEGIN
  PERFORM need_module(actor, e, 'Reports');
  RETURN (SELECT COALESCE(json_agg(json_build_object('krama', k.name, 'kind', k.kind, 'standalone', k.standalone, 'report', rp.name,
            'question', rp.question_text, 'metric', rp.metric, 'answer', report_answer(rp.metric, e)) ORDER BY k.kind DESC, k.name, rp.name), '[]')
            FROM report rp JOIN krama k USING (krama_id)
           WHERE (k.owner_entity = e OR k.owner_entity IS NULL) AND k.status = 'Published' AND (k.kind = 'Report and Analytics' OR k.owner_entity = e));
END $$;

CREATE FUNCTION api_module(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
DECLARE m uuid := (b->>'module_id')::uuid; k record;
BEGIN
  SELECT * INTO k FROM krama WHERE krama_id = m;
  IF k.kind <> 'Module' THEN RAISE EXCEPTION 'Not a Module'; END IF;
  IF j(b, 'add') IS NOT NULL THEN
    IF NOT can_design(actor, m) THEN RAISE EXCEPTION 'You cannot change this Module'; END IF;
    IF k.status = 'Published' THEN RAISE EXCEPTION 'A Published Module is frozen; create a new version'; END IF;
    IF NOT EXISTS (SELECT 1 FROM krama WHERE krama_id = (b->>'add')::uuid AND status = 'Published' AND kind IN ('Workflow','Report and Analytics')) THEN
      RAISE EXCEPTION 'A Module is made only from Published Workflow and Report and Analytics Kramas';
    END IF;
    INSERT INTO module_member VALUES (m, (b->>'add')::uuid) ON CONFLICT DO NOTHING;
  END IF;
  IF j(b, 'remove') IS NOT NULL THEN
    IF NOT can_design(actor, m) THEN RAISE EXCEPTION 'You cannot change this Module'; END IF;
    DELETE FROM module_member WHERE module_id = m AND member_id = (b->>'remove')::uuid;
  END IF;
  RETURN json_build_object(
    'members', (SELECT COALESCE(json_agg(json_build_object('krama_id', x.krama_id, 'name', x.name, 'kind', x.kind, 'version', x.version)), '[]')
                FROM module_member mm JOIN krama x ON x.krama_id = mm.member_id WHERE mm.module_id = m),
    'available', (SELECT COALESCE(json_agg(json_build_object('krama_id', x.krama_id, 'name', x.name, 'kind', x.kind, 'version', x.version) ORDER BY x.name), '[]')
                FROM krama x WHERE x.status = 'Published' AND x.kind IN ('Workflow','Report and Analytics')
                  AND (x.owner_entity IS NOT DISTINCT FROM k.owner_entity OR x.ownership_type = 'Platform Built Platform Owned')
                  AND NOT EXISTS (SELECT 1 FROM module_member mm WHERE mm.module_id = m AND mm.member_id = x.krama_id)));
END $$;

CREATE FUNCTION api_components(actor uuid, b jsonb) RETURNS json LANGUAGE sql STABLE AS $$
  SELECT COALESCE(json_agg(json_build_object('component_id', component_id, 'level', level, 'name', name, 'ownership', ownership, 'description', description, 'body', body)
                  ORDER BY CASE level WHEN 'Stage' THEN 1 WHEN 'Topic' THEN 2 ELSE 3 END, name), '[]') FROM component
$$;

-- Insert a component into a Krama being designed: a Stage (with its topics), a Topic (into a stage) or a Question (into a topic)
CREATE FUNCTION api_insert_component(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
DECLARE c record; k uuid := (b->>'krama_id')::uuid; st uuid := NULLIF(b->>'stage_id', '')::uuid; tp uuid := NULLIF(b->>'topic_id', '')::uuid;
        t jsonb; qq jsonb; ns uuid; nt uuid; seqn int;
BEGIN
  IF NOT can_design(actor, k) THEN RAISE EXCEPTION 'You cannot change this Krama'; END IF;
  SELECT * INTO c FROM component WHERE component_id = (b->>'component_id')::uuid;
  IF c IS NULL THEN RAISE EXCEPTION 'Component not found'; END IF;
  IF c.level = 'Stage' THEN
    INSERT INTO stage (krama_id, name, seq, path) VALUES (k, c.name, COALESCE((SELECT max(seq) FROM stage WHERE krama_id = k), 0) + 1, COALESCE(c.body->>'path', 'PR only')) RETURNING stage_id INTO ns;
    FOR t IN SELECT * FROM jsonb_array_elements(c.body->'topics') LOOP
      INSERT INTO topic (stage_id, name, seq, path) VALUES (ns, t->>'name', COALESCE((SELECT max(seq) FROM topic WHERE stage_id = ns), 0) + 1, COALESCE(t->>'path', 'PR only')) RETURNING topic_id INTO nt;
      seqn := 0;
      FOR qq IN SELECT * FROM jsonb_array_elements(t->'questions') LOOP
        seqn := seqn + 1;
        INSERT INTO question (topic_id, text, seq, flow_option, ask_in, rules, due_days) VALUES (nt, qq->>'text', seqn, COALESCE(qq->>'flow_option', 'Decision'), COALESCE(qq->>'ask_in', 'PR'), qq->>'rules', 7);
      END LOOP;
    END LOOP;
  ELSIF c.level = 'Topic' THEN
    IF st IS NULL THEN RAISE EXCEPTION 'Pick the stage to put this topic in'; END IF;
    t := c.body->'topics'->0;
    INSERT INTO topic (stage_id, name, seq, path) VALUES (st, t->>'name', COALESCE((SELECT max(seq) FROM topic WHERE stage_id = st), 0) + 1,
           LEAST_PATH((SELECT path FROM stage WHERE stage_id = st), COALESCE(t->>'path', 'PR only'))) RETURNING topic_id INTO nt;
    seqn := 0;
    FOR qq IN SELECT * FROM jsonb_array_elements(t->'questions') LOOP
      seqn := seqn + 1;
      INSERT INTO question (topic_id, text, seq, flow_option, ask_in, rules, due_days) VALUES (nt, qq->>'text', seqn, COALESCE(qq->>'flow_option', 'Decision'), 'PR', qq->>'rules', 7);
    END LOOP;
  ELSE
    IF tp IS NULL THEN RAISE EXCEPTION 'Pick the topic to put this question in'; END IF;
    FOR qq IN SELECT * FROM jsonb_array_elements(c.body->'questions') LOOP
      INSERT INTO question (topic_id, text, seq, flow_option, ask_in, rules, due_days)
      VALUES (tp, qq->>'text', COALESCE((SELECT max(seq) FROM question WHERE topic_id = tp), 0) + 1, COALESCE(qq->>'flow_option', 'Decision'), 'PR', qq->>'rules', 7);
    END LOOP;
  END IF;
  PERFORM log_krama(k, actor, 'Component inserted', c.name);
  RETURN json_build_object('ok', true);
END $$;

CREATE FUNCTION least_path(a text, b text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN path_rank(a) < path_rank(b) THEN a ELSE b END
$$;

-- Reopening a Dropped item offers a new instance with the same data: earlier agreed answers stay agreed
CREATE FUNCTION api_start_again(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
DECLARE r run; nr uuid; x record;
BEGIN
  SELECT * INTO r FROM run WHERE run_id = (b->>'run_id')::uuid;
  IF r IS NULL THEN RAISE EXCEPTION 'Task not found'; END IF;
  IF r.requestor_id <> actor THEN RAISE EXCEPTION 'Only the Requestor/Conductor starts it again'; END IF;
  IF r.result IS DISTINCT FROM 'Unfulfilled' THEN RAISE EXCEPTION 'Only a Dropped (Unfulfilled) task starts again as a new instance'; END IF;
  nr := activate(r.item_id, actor, r.counterparty, r.relationship, r.krama_id);
  FOR x IN SELECT o.* FROM question_run o WHERE o.run_id = r.run_id AND o.answer_state = 'Agreed' LOOP
    UPDATE question_run SET answer = x.answer, answer_data = x.answer_data, source = x.source, answer_state = 'Agreed', status = 'Closed', closed_as = 'Success'
     WHERE run_id = nr AND question_id = x.question_id;
  END LOOP;
  PERFORM log_run(nr, actor, 'Started again', 'From ' || r.instance_code || '; agreed answers carried over');
  RETURN json_build_object('run_id', nr);
END $$;

-- =====================================================================================
-- Demo data for the new screens
-- =====================================================================================
SELECT set_config('demo.seeding', 'on', false);

UPDATE users SET compane_id = 'CMP-' || upper(substr(md5(user_id::text), 1, 6)), mobile = '+91 98' || substr(md5(name), 1, 8)
 WHERE user_type = 'Individual';
UPDATE users SET personal_email = lower(replace(name, ' ', '.')) || '@example.com' WHERE user_type = 'Individual' AND personal_email IS NULL;
INSERT INTO personal_document (owner_id, kind, status, at)
SELECT user_id, k, CASE WHEN k = 'National ID' THEN 'Verified' ELSE 'Not connected' END, CASE WHEN k = 'National ID' THEN clock_timestamp() END
  FROM users, unnest(ARRAY['National ID','Tax ID','Passport']) k WHERE user_type = 'Individual';
UPDATE users SET identity_verified = true WHERE user_type = 'Individual';

UPDATE person_entity_link l SET work_email = lower(split_part(user_name(l.person_id), ' ', 1)) || '@' || lower(replace(split_part(user_name(l.company_user_id), ' ', 1), ' ', '')) || '.in',
       designation = CASE WHEN l.is_entity_super_user THEN 'Director' ELSE 'Manager' END,
       sits = CASE WHEN l.is_entity_super_user THEN 'Admin above Dept/BU head' ELSE 'Dept/BU head or below' END;
UPDATE company SET category = 'Trading', sub_category = 'Distribution', size = 'Small', business_model = 'Functional',
       work_email = 'admin@' || lower(split_part(user_name(user_id), ' ', 1)) || '.in';

-- Grades, designations and Work Personas for Ledgerline's Finance
DO $$
DECLARE fin uuid; g1 uuid; g2 uuid; p1 uuid; e uuid;
BEGIN
  SELECT d.dept_bu_id, d.company_user_id INTO fin, e FROM dept_bu d JOIN users u ON u.user_id = d.company_user_id WHERE u.name = 'Ledgerline Traders' AND d.name = 'Finance';
  INSERT INTO grade (dept_bu_id, name, rank) VALUES (fin, 'Head', 1) RETURNING grade_id INTO g1;
  INSERT INTO grade (dept_bu_id, name, rank) VALUES (fin, 'Executive', 2) RETURNING grade_id INTO g2;
  INSERT INTO designation (dept_bu_id, grade_id, name) VALUES (fin, g1, 'Finance Head'), (fin, g2, 'Accounts Executive');
  INSERT INTO work_persona (entity_id, dept_bu_id, grade_id, name, modules) VALUES (e, fin, g1, 'Finance Head', ARRAY['WOM','Krama']) RETURNING persona_id INTO p1;
  INSERT INTO work_persona (entity_id, dept_bu_id, grade_id, name, reports_to) VALUES (e, fin, g2, 'Accounts Executive', p1);
END $$;

-- Connections: Ledgerline buys from Northwind (connected); Ledgerline invited Orbit (pending)
INSERT INTO entity_connection (from_entity, to_entity, to_name, relationship, state, invited_by)
SELECT a.user_id, b.user_id, b.name, 'Vendor', 'Connected', NULL FROM users a, users b WHERE a.name = 'Ledgerline Traders' AND b.name = 'Northwind Supplies';
INSERT INTO entity_connection (from_entity, to_entity, to_name, relationship, state, invited_by)
SELECT a.user_id, b.user_id, b.name, 'Pre-vendor', 'Pending', NULL FROM users a, users b WHERE a.name = 'Ledgerline Traders' AND b.name = 'Orbit IT Services';

-- Mail and chat
INSERT INTO mail_message (owner_id, folder, from_addr, to_addr, subject, body, work)
SELECT u.user_id, 'Inbox', 'accounts@northwind.in', 'admin@ledgerline.in', 'Invoice INV-1042 for October', 'Please find our invoice for office supplies attached.', 'Answer to Vendor invoice · INS-0001'
  FROM users u WHERE u.name = 'Ledgerline Traders';
INSERT INTO mail_message (owner_id, folder, from_addr, to_addr, subject, body, work)
SELECT u.user_id, 'Inbox', 'sales@orbit.in', 'admin@ledgerline.in', 'Service acceptance for November', 'Can we schedule the acceptance call next week?', NULL
  FROM users u WHERE u.name = 'Ledgerline Traders';
INSERT INTO chat_message (from_party, to_party, by_person, body)
SELECT a.user_id, b.user_id, (SELECT user_id FROM users WHERE name = 'Asha Rao'), 'The signed delivery note is in the Vendor room.'
  FROM users a, users b WHERE a.name = 'Northwind Supplies' AND b.name = 'Ledgerline Traders';

-- Reusable components (platform built, platform owned; generic names)
INSERT INTO component (level, name, description, body) VALUES
 ('Question', 'National ID', 'A person''s national ID: validated by integration where the receiving country accepts it, otherwise the alternate route.',
  '{"questions":[{"text":"National ID (integration)","flow_option":"Input field","rules":"Validate through the country''s ID integration."},{"text":"National ID (alternate)","flow_option":"File drop","rules":"Where the ID is not accepted: an attested copy."}]}'),
 ('Question', 'Address proof', 'One accepted address document.', '{"questions":[{"text":"Address proof","flow_option":"File drop","rules":"Any one accepted address document, not older than three months."}]}'),
 ('Question', 'Bank details', 'Account details checked against a cancelled cheque.', '{"questions":[{"text":"Bank details","flow_option":"Checklist","rules":"Account name, IFSC and a cancelled cheque."}]}'),
 ('Topic', 'Director — new appointment', 'Consent, identity and address for a new director.',
  '{"topics":[{"name":"Director — new appointment","path":"PR → IR","questions":[{"text":"Consent to act","flow_option":"Signature panel"},{"text":"Identity","flow_option":"File drop"},{"text":"Address","flow_option":"File drop"}]}]}'),
 ('Topic', 'Registration — renewal', 'The renewal application and its acknowledgement.',
  '{"topics":[{"name":"Registration — renewal","path":"PR → IR","questions":[{"text":"Renewal application","flow_option":"File drop"},{"text":"Acknowledgement","flow_option":"Input field"}]}]}'),
 ('Stage', 'Vendor set-up', 'Everything needed before a vendor can be paid.',
  '{"path":"PR → IR → ER","topics":[{"name":"Vendor details","path":"PR → IR → ER","questions":[{"text":"Registered name","flow_option":"Input field","ask_in":"ER"},{"text":"Tax registration","flow_option":"File drop","ask_in":"ER"}]},{"name":"Bank details","path":"PR → IR","questions":[{"text":"Bank details","flow_option":"Checklist","ask_in":"IR"}]}]}');

-- A standalone Report and Analytics Krama (platform) and a Module (Ledgerline)
DO $$
DECLARE k uuid; m uuid; s uuid; t uuid; via uuid; e uuid;
BEGIN
  INSERT INTO krama (code, name, owner_entity, ownership_type, status, kind, standalone, tag_kind)
  VALUES ('RAW', 'Work overview', NULL, 'Platform Built Platform Owned', 'Published', 'Report and Analytics', true, 'Business') RETURNING krama_id INTO k;
  INSERT INTO stage (krama_id, name, seq, path) VALUES (k, 'Work', 1, 'PR only') RETURNING stage_id INTO s;
  INSERT INTO topic (stage_id, name, seq, path) VALUES (s, 'Where work stands', 1, 'PR only') RETURNING topic_id INTO t;
  INSERT INTO report (krama_id, name, question_text, metric) VALUES
   (k, 'Tasks by status', 'How many tasks are open, fulfilled or unfulfilled?', 'runs_by_status'),
   (k, 'Answers by state', 'Where do all the answers stand?', 'questions_by_state'),
   (k, 'Overdue', 'Which open questions are past their due date, and by how many days?', 'overdue_questions'),
   (k, 'Tasks by item', 'Which catalogue items are used most?', 'runs_by_item'),
   (k, 'Estimates', 'What is estimated against actual?', 'estimate_totals');
  SELECT user_id INTO e FROM users WHERE name = 'Ledgerline Traders';
  INSERT INTO krama (code, name, owner_entity, ownership_type, status, kind, pool_mark, tag_kind)
  VALUES ('PUR', 'Purchasing', e, 'Entity Built Entity Owned', 'Created', 'Module', 'Entity Built', 'Business') RETURNING krama_id INTO m;
  SELECT krama_id INTO via FROM krama WHERE owner_entity = e AND code = 'VIA' AND status = 'Published' LIMIT 1;
  IF via IS NOT NULL THEN INSERT INTO module_member VALUES (m, via); END IF;
  INSERT INTO module_member VALUES (m, k);
END $$;

-- A file attached in an answer, and one in a registry
UPDATE question_run x SET answer_data = '{"file":"inv-1042.pdf","mobility":"Mobile","evidence":true}'::jsonb
  FROM question q WHERE q.question_id = x.question_id AND q.text = 'Vendor invoice' AND x.answer IS NOT NULL;
INSERT INTO registry_entry (registry_id, kind, title, status, source_room_id)
SELECT g.registry_id, 'File', 'Purchase order PO-77.pdf', 'Approved', g.room_id FROM registry g JOIN room rm USING (room_id) JOIN run r USING (run_id)
 WHERE r.instance_code = 'INS-0001' AND rm.kind = 'IR';

SELECT set_config('demo.seeding', 'off', false);


-- New Report and Analytics or Module Krama in the entity's console (Workflow Kramas are made in the console as before)
CREATE FUNCTION api_new_krama(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
DECLARE e uuid := (b->>'entity_id')::uuid; k uuid;
BEGIN
  PERFORM need_admin(actor, e);
  IF j(b, 'kind') NOT IN ('Report and Analytics','Module') THEN RAISE EXCEPTION 'Pick Report and Analytics or Module'; END IF;
  IF j(b, 'name') IS NULL THEN RAISE EXCEPTION 'Name it'; END IF;
  INSERT INTO krama (code, name, owner_entity, ownership_type, pool_mark, status, kind, standalone, tag_kind)
  VALUES (upper(substr(regexp_replace(j(b, 'name'), '[^A-Za-z]', '', 'g'), 1, 3)), j(b, 'name'), e, 'Entity Built Entity Owned', 'Entity Built', 'Created',
          j(b, 'kind'), j(b, 'kind') = 'Report and Analytics' AND COALESCE((b->>'standalone')::boolean, true), 'Business')
  RETURNING krama_id INTO k;
  PERFORM log_krama(k, actor, 'Created', j(b, 'kind') || ' · ' || j(b, 'name'));
  RETURN json_build_object('krama_id', k);
END $$;

-- Modules and Report and Analytics Kramas of an entity (and the platform's)
CREATE FUNCTION api_kinds(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql STABLE AS $$
DECLARE e uuid := (b->>'entity_id')::uuid;
BEGIN
  PERFORM need_member(actor, e);
  RETURN (SELECT COALESCE(json_agg(json_build_object('krama_id', krama_id, 'name', name, 'kind', kind, 'standalone', standalone, 'status', status,
            'owner', COALESCE(user_name(owner_entity), 'Platform'), 'can_design', can_design(actor, krama_id),
            'reports', (SELECT COALESCE(json_agg(json_build_object('name', name, 'question_text', question_text, 'metric', metric)), '[]') FROM report rp WHERE rp.krama_id = k.krama_id))
            ORDER BY kind, name), '[]')
            FROM krama k WHERE kind IN ('Report and Analytics','Module') AND (owner_entity = e OR owner_entity IS NULL));
END $$;

CREATE FUNCTION api_add_report(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
DECLARE k uuid := (b->>'krama_id')::uuid;
BEGIN
  IF NOT can_design(actor, k) THEN RAISE EXCEPTION 'You cannot change this Krama'; END IF;
  IF j(b, 'name') IS NULL OR j(b, 'question_text') IS NULL THEN RAISE EXCEPTION 'Name the report and the question it answers'; END IF;
  INSERT INTO report (krama_id, name, question_text, metric) VALUES (k, j(b, 'name'), j(b, 'question_text'), COALESCE(j(b, 'metric'), 'questions_by_state'));
  RETURN json_build_object('ok', true);
END $$;
