-- Compane ER demo, FRD v3.0 (Krama doctrine aligned)
-- Masters → Krama design (Create) → catalogue and runs (Connect, Conduct, Conserve)

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ======================= Masters =======================

CREATE TABLE expertise (
  expertise_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name         text NOT NULL UNIQUE,
  role         text,
  purpose      text
);

-- Persona types (the live backend's entity persona classification, plus a Human placeholder).
-- A broader type covers the narrower types under it.
CREATE TABLE persona_type (
  persona_type_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug            text NOT NULL UNIQUE,
  display_name    text NOT NULL,
  party_type      text NOT NULL DEFAULT 'Entity' CHECK (party_type IN ('Entity','Person')),
  parent_id       uuid REFERENCES persona_type(persona_type_id),
  depth           integer NOT NULL DEFAULT 0,
  description     text
);

CREATE TABLE company_type (
  company_type_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sub_type        text NOT NULL UNIQUE
                  CHECK (sub_type IN ('Sole proprietor','Partnership firm','Pvt Ltd','LLP','Public Ltd','Trust')),
  structure       text NOT NULL DEFAULT 'Functional' CHECK (structure IN ('Functional','Business Unit'))
);

CREATE TABLE company_type_dept_bu (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_type_id uuid NOT NULL REFERENCES company_type(company_type_id) ON DELETE CASCADE,
  name            text NOT NULL
);

-- People, companies and AI
CREATE TABLE users (
  user_id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name           text NOT NULL,
  personal_email text UNIQUE,
  user_type      text NOT NULL DEFAULT 'Individual' CHECK (user_type IN ('Individual','Company','AI')),
  is_super_user  boolean NOT NULL DEFAULT false,      -- platform super-user
  expertise_ids  uuid[] NOT NULL DEFAULT '{}'
);

CREATE TABLE company (
  company_id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL UNIQUE REFERENCES users(user_id) ON DELETE CASCADE,
  company_type_id uuid NOT NULL REFERENCES company_type(company_type_id),
  persona_type_id uuid REFERENCES persona_type(persona_type_id)   -- the entity's own persona type
);

CREATE TABLE dept_bu (
  dept_bu_id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_user_id uuid NOT NULL REFERENCES users(user_id),
  name            text NOT NULL
);

-- Role definitions: templates per company type, or a company's own copy. They describe
-- positions only; acting rights in a run come from seats.
CREATE TABLE role_definition (
  role_id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_type_id uuid REFERENCES company_type(company_type_id) ON DELETE CASCADE,
  company_user_id uuid REFERENCES users(user_id),
  name            text NOT NULL,
  description     text,
  CHECK (num_nonnulls(company_type_id, company_user_id) = 1)
);

-- A person can belong to several entities; a full-time employee's further links need the employer's approval
CREATE TABLE person_entity_link (
  link_id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  person_id            uuid NOT NULL REFERENCES users(user_id),
  company_user_id      uuid NOT NULL REFERENCES users(user_id),
  dept_bu_id           uuid REFERENCES dept_bu(dept_bu_id),
  role_id              uuid REFERENCES role_definition(role_id),
  is_full_time         boolean NOT NULL DEFAULT false,
  employer_approved    boolean NOT NULL DEFAULT false,
  is_entity_super_user boolean NOT NULL DEFAULT false,
  UNIQUE (person_id, company_user_id)
);

-- ======================= Krama design (Create) =======================

CREATE TABLE krama (
  krama_id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code             text NOT NULL,
  name             text NOT NULL,
  owner_entity     uuid REFERENCES users(user_id),           -- empty = platform console
  ownership_type   text NOT NULL CHECK (ownership_type IN
                   ('Platform Built Platform Owned','Platform Built Entity Owned','Entity Built Entity Owned')),
  pool_mark        text CHECK (pool_mark IN ('Entity Built','Entity Customised','Platform built')),
  status           text NOT NULL DEFAULT 'Created'
                   CHECK (status IN ('Created','Learning and Training','Testing','Published')),
  version          integer NOT NULL DEFAULT 1,
  previous_version uuid REFERENCES krama(krama_id),
  source_krama_id  uuid REFERENCES krama(krama_id),          -- platform Krama this copy was imported from
  tag_kind         text CHECK (tag_kind IN ('Business','Compliance')),
  tag_domain       text,                                     -- shown as "Module"; "Domain" is never shown
  lifetime_years   integer NOT NULL DEFAULT 10,
  what_changed     text
);

CREATE TABLE room_template (
  room_template_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  krama_id         uuid NOT NULL REFERENCES krama(krama_id) ON DELETE CASCADE,
  kind             text NOT NULL CHECK (kind IN ('PR','IR','ER')),
  label            text NOT NULL,
  UNIQUE (krama_id, kind)
);

CREATE TABLE stage (
  stage_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  krama_id uuid NOT NULL REFERENCES krama(krama_id) ON DELETE CASCADE,
  name     text NOT NULL,
  seq      integer NOT NULL DEFAULT 1,
  path     text NOT NULL DEFAULT 'PR only' CHECK (path IN ('PR only','PR → IR','PR → IR → ER'))
);

CREATE TABLE topic (
  topic_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  stage_id uuid NOT NULL REFERENCES stage(stage_id) ON DELETE CASCADE,
  name     text NOT NULL,
  seq      integer NOT NULL DEFAULT 1,
  path     text NOT NULL DEFAULT 'PR only' CHECK (path IN ('PR only','PR → IR','PR → IR → ER')),
  is_output boolean NOT NULL DEFAULT false      -- an output document built from this topic's agreed answers
);

CREATE TABLE question (
  question_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  topic_id    uuid NOT NULL REFERENCES topic(topic_id) ON DELETE CASCADE,
  text        text NOT NULL,
  seq         integer NOT NULL DEFAULT 1,
  flow_option text NOT NULL DEFAULT 'Decision' CHECK (flow_option IN
              ('Decision','Input field','Choice list','Checklist','File drop','Assign','Table grid','Compare box','Finding control','Signature panel')),
  -- setup for the chosen flow option (only the fields that option uses are read)
  setup_options text,      -- Choice list options, or Checklist items: one per line
  setup_choices text,      -- Checklist: the choices each item gets, one per line
  setup_multi   boolean NOT NULL DEFAULT false,   -- Choice list: pick many
  setup_columns text,      -- Table grid: column names, one per line
  setup_limit   numeric,   -- Compare box: largest allowed difference
  also_needs    text CHECK (also_needs IN ('File drop','Finding control')),   -- an allowed second answer type
  ask_in      text NOT NULL DEFAULT 'PR' CHECK (ask_in IN ('PR','IR','ER')),  -- room where it is answered
  rules       text,                                                             -- what is needed, in plain English
  due_days    integer NOT NULL DEFAULT 7
);

-- Sequencing: a question waits for its predecessors; unlinked questions run concurrently
CREATE TABLE question_link (
  link_id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  question_id    uuid NOT NULL REFERENCES question(question_id) ON DELETE CASCADE,
  predecessor_id uuid NOT NULL REFERENCES question(question_id) ON DELETE CASCADE,
  UNIQUE (question_id, predecessor_id),
  CHECK (question_id <> predecessor_id)
);

CREATE TABLE report (
  report_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  krama_id      uuid NOT NULL REFERENCES krama(krama_id) ON DELETE CASCADE,
  name          text NOT NULL,
  question_text text NOT NULL
);

-- Relationship matrix: a Krama maps to a persona type under a relationship, never to the relationship alone
CREATE TABLE krama_relationship (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  krama_id        uuid NOT NULL REFERENCES krama(krama_id) ON DELETE CASCADE,
  relationship    text NOT NULL CHECK (relationship IN ('Department','Business Unit','Pre-client','Client','Pre-vendor','Vendor')),
  party_type      text NOT NULL DEFAULT 'Entity' CHECK (party_type IN ('Entity','Person')),
  persona_type_id uuid NOT NULL REFERENCES persona_type(persona_type_id),
  UNIQUE (krama_id, relationship, party_type, persona_type_id)
);

-- Capability catalogue: built once, applied wherever needed; each declares the boundaries it may apply to
CREATE TABLE capability (
  code       text PRIMARY KEY,
  name       text NOT NULL,
  what       text NOT NULL,
  boundaries text[] NOT NULL,
  seq        integer NOT NULL
);

CREATE TABLE capability_use (
  use_id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  krama_id    uuid NOT NULL REFERENCES krama(krama_id) ON DELETE CASCADE,
  code        text NOT NULL REFERENCES capability(code),
  stage_id    uuid REFERENCES stage(stage_id) ON DELETE CASCADE,
  topic_id    uuid REFERENCES topic(topic_id) ON DELETE CASCADE,
  question_id uuid REFERENCES question(question_id) ON DELETE CASCADE,
  note        text,
  CHECK (num_nonnulls(stage_id, topic_id, question_id) = 1)
);

CREATE TABLE expertise_required (
  requirement_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  stage_id       uuid REFERENCES stage(stage_id) ON DELETE CASCADE,
  topic_id       uuid REFERENCES topic(topic_id) ON DELETE CASCADE,
  question_id    uuid REFERENCES question(question_id) ON DELETE CASCADE,
  expertise_id   uuid NOT NULL REFERENCES expertise(expertise_id),
  mapped_as      text NOT NULL CHECK (mapped_as IN ('Consumer','Provider')),
  CHECK (num_nonnulls(stage_id, topic_id, question_id) = 1)
);

-- ======================= Connect, Conduct, Conserve =======================

-- Catalogue domains (platform owned, shared): Compliance, Business › Process or Business › Commercial → Domain → Domain persona
CREATE TABLE catalogue_domain (
  domain_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  catalogue text NOT NULL CHECK (catalogue IN ('Compliance','Process','Commercial')),
  name      text NOT NULL,
  UNIQUE (catalogue, name)
);

-- A Domain persona carries metadata only (like a constitution), never working data
CREATE TABLE domain_persona (
  domain_persona_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  domain_id         uuid NOT NULL REFERENCES catalogue_domain(domain_id),
  name              text NOT NULL,
  metadata          text,
  UNIQUE (domain_id, name)
);

-- Platform catalogue library (domain form, shared): metadata only, mapped to seller and buyer persona types
CREATE TABLE library_item (
  library_item_id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind                   text NOT NULL CHECK (kind IN ('SKU','SDU','Services')),
  name                   text NOT NULL,
  metadata               text,
  domain_persona_id      uuid REFERENCES domain_persona(domain_persona_id),
  seller_persona_type_id uuid REFERENCES persona_type(persona_type_id),
  buyer_persona_type_id  uuid REFERENCES persona_type(persona_type_id)
);

CREATE SEQUENCE catalogue_code_seq;

-- The entity's instance of a catalogue item (entity data), with the Kramas assigned to it.
-- Only priced things are catalogue items; it stays unpublished until its review (Share and Assign) closes as Success.
CREATE TABLE catalogue_item (
  item_id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_user_id   uuid NOT NULL REFERENCES users(user_id),
  catalogue_code    text NOT NULL UNIQUE DEFAULT 'CAT-' || lpad(nextval('catalogue_code_seq')::text, 4, '0'),
  name              text NOT NULL,
  item_type         text NOT NULL DEFAULT 'Services' CHECK (item_type IN ('SKU','SDU','Services')),
  catalogue         text NOT NULL DEFAULT 'Process' CHECK (catalogue IN ('Compliance','Process','Commercial')),
  domain_persona_id uuid REFERENCES domain_persona(domain_persona_id),
  library_item_id   uuid REFERENCES library_item(library_item_id),
  library_use       text CHECK (library_use IN ('As it is','Customised')),
  release           text NOT NULL DEFAULT 'Alpha' CHECK (release IN ('Alpha','Pilot','Beta','General Availability')),
  review            text NOT NULL DEFAULT 'Not shared' CHECK (review IN ('Not shared','In review','Success')),
  -- Visibility: External → Discover and Connect, Client or Vendor → Generic or Customised (names);
  --             Internal → Host Dept/BU → Internal client (Generic = all Dept/BUs, Customised = names) or Self
  visibility_scope  text CHECK (visibility_scope IN ('External','Internal')),
  visibility_audience text CHECK (visibility_audience IN ('Discover and Connect','Client','Vendor','Internal client','Self')),
  visibility_reach  text CHECK (visibility_reach IN ('Generic','Customised')),
  visibility_names  uuid[] NOT NULL DEFAULT '{}',   -- entities (External) or Dept/BUs (Internal) when Customised
  host_dept_bu_id   uuid REFERENCES dept_bu(dept_bu_id),
  -- Content: material only, at item level; how it looks is decided by the website
  content_title     text,
  main_image        text,
  content_blocks    jsonb NOT NULL DEFAULT '[]',     -- [{kind: Text|Image|Video, body}]
  -- Marketing
  landing_page      text,
  landing_status    text CHECK (landing_status IN ('External page','Generated','Approved')),
  brand_name        text,
  category          text,
  sub_category      text,
  competitors       jsonb NOT NULL DEFAULT '[]',     -- [{brand, business, website}]
  CHECK ((visibility_scope = 'External' AND visibility_audience IN ('Discover and Connect','Client','Vendor'))
      OR (visibility_scope = 'Internal' AND visibility_audience IN ('Internal client','Self'))
      OR visibility_scope IS NULL)
);

-- Variants: everything variant-specific (pricing, tax, wording, one offer at a time, journey)
CREATE TABLE catalogue_variant (
  variant_id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  item_id           uuid NOT NULL REFERENCES catalogue_item(item_id) ON DELETE CASCADE,
  name              text NOT NULL,
  seq               integer NOT NULL DEFAULT 1,
  pricing_type      text NOT NULL DEFAULT 'Fixed' CHECK (pricing_type IN ('Fixed','Per unit','Per hour','Per sprint','Package','Request quote')),
  price             numeric(14,2),
  tax_mode          text NOT NULL DEFAULT '+ tax' CHECK (tax_mode IN ('+ tax','tax included')),
  hsn_sac           text,
  gst_rate          numeric(5,2),
  quotation_wording text,
  invoice_wording   text,
  offer_kind        text CHECK (offer_kind IN ('%','Fixed')),
  offer_amount      numeric(14,2),
  offer_for         text NOT NULL DEFAULT 'Everyone' CHECK (offer_for IN ('Everyone','Named clients')),
  offer_names       uuid[] NOT NULL DEFAULT '{}',
  offer_until       date,
  promo             text,                            -- the offer in words, or 'Not applicable'
  UNIQUE (item_id, name)
);

-- Journey: one row per variant, each step picked from Published Kramas
CREATE TABLE catalogue_journey_step (
  step_id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  variant_id uuid NOT NULL REFERENCES catalogue_variant(variant_id) ON DELETE CASCADE,
  step       text NOT NULL CHECK (step IN ('Opportunity','Deal','Order management','Process')),
  krama_id   uuid REFERENCES krama(krama_id),
  UNIQUE (variant_id, step)
);

-- Dependencies: Krama level (another flow) or catalogue level (another item); before or after, never blocking
CREATE TABLE catalogue_dependency (
  dependency_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  variant_id    uuid NOT NULL REFERENCES catalogue_variant(variant_id) ON DELETE CASCADE,
  level         text NOT NULL CHECK (level IN ('Krama','Catalogue')),
  krama_id      uuid REFERENCES krama(krama_id),
  dep_item_id   uuid REFERENCES catalogue_item(item_id),
  timing        text NOT NULL CHECK (timing IN ('Before','After')),
  done_outside  boolean NOT NULL DEFAULT false,
  CHECK ((level = 'Krama' AND krama_id IS NOT NULL AND dep_item_id IS NULL)
      OR (level = 'Catalogue' AND dep_item_id IS NOT NULL AND krama_id IS NULL))
);

-- Seats: one person or party per seat; the Fulfiller may map several vendors (a quote comparison)
CREATE TABLE catalogue_seat (
  catalogue_seat_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  item_id         uuid NOT NULL REFERENCES catalogue_item(item_id) ON DELETE CASCADE,
  seat            text NOT NULL CHECK (seat IN ('Buyer','Seller','Fulfiller','Assurer','Representation')),
  side            text NOT NULL CHECK (side IN ('Internal','External')),
  dept_bu_id      uuid REFERENCES dept_bu(dept_bu_id),
  party_id        uuid REFERENCES users(user_id),        -- a client or vendor entity, including pre-clients and pre-vendors
  vendor_item_id  uuid REFERENCES catalogue_item(item_id), -- Fulfiller: the vendor's own catalogue item, mapped
  CHECK ((side = 'Internal' AND dept_bu_id IS NOT NULL AND party_id IS NULL)
      OR (side = 'External' AND party_id IS NOT NULL AND dept_bu_id IS NULL))
);
CREATE UNIQUE INDEX catalogue_seat_one ON catalogue_seat (item_id, seat) WHERE seat <> 'Fulfiller';
CREATE UNIQUE INDEX catalogue_seat_party ON catalogue_seat (item_id, seat, coalesce(dept_bu_id, party_id));

CREATE TABLE catalogue_item_krama (
  id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  item_id  uuid NOT NULL REFERENCES catalogue_item(item_id) ON DELETE CASCADE,
  krama_id uuid NOT NULL REFERENCES krama(krama_id),
  UNIQUE (item_id, krama_id)
);

CREATE SEQUENCE instance_seq;

CREATE TABLE run (
  run_id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  instance_code   text NOT NULL UNIQUE,
  amendment_no    integer NOT NULL DEFAULT 0,
  item_id         uuid NOT NULL REFERENCES catalogue_item(item_id),
  krama_id        uuid NOT NULL REFERENCES krama(krama_id),
  company_user_id uuid NOT NULL REFERENCES users(user_id),       -- the entity running it
  counterparty    uuid REFERENCES users(user_id),                -- the other entity, if any
  relationship    text CHECK (relationship IN ('Department','Business Unit','Pre-client','Client','Pre-vendor','Vendor')),
  requestor_id    uuid NOT NULL REFERENCES users(user_id),
  fy              text NOT NULL,
  status          text NOT NULL DEFAULT 'Open' CHECK (status IN ('Open','Closed')),
  result          text CHECK (result IN ('Fulfilled','Unfulfilled')),
  locked_at       timestamptz,
  started_on      date NOT NULL DEFAULT current_date
);

CREATE TABLE room (
  room_id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id         uuid NOT NULL REFERENCES run(run_id) ON DELETE CASCADE,
  kind           text NOT NULL CHECK (kind IN ('PR','IR','ER')),
  name           text NOT NULL,
  with_entity    uuid REFERENCES users(user_id),           -- ER: the entity on the other side
  parent_room_id uuid REFERENCES room(room_id),            -- a child ER forks from an ER
  permission     text NOT NULL DEFAULT 'Not needed' CHECK (permission IN ('Not needed','Requested','Granted')),
  created_at     timestamptz NOT NULL DEFAULT clock_timestamp()
);

-- Where each topic sits: a topic is Retained in every room its path allows until it is Deleted from one
CREATE TABLE room_topic (
  room_id  uuid NOT NULL REFERENCES room(room_id) ON DELETE CASCADE,
  topic_id uuid NOT NULL REFERENCES topic(topic_id),
  PRIMARY KEY (room_id, topic_id)
);

-- Registry: per room, named, with a short description; holds Events, Files or Both. Calendar sits inside it.
CREATE TABLE registry (
  registry_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id     uuid NOT NULL REFERENCES room(room_id) ON DELETE CASCADE,
  name        text NOT NULL,
  description text,
  holds       text NOT NULL DEFAULT 'Both' CHECK (holds IN ('Events','Files','Both'))
);

CREATE TABLE registry_entry (
  entry_id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  registry_id    uuid NOT NULL REFERENCES registry(registry_id) ON DELETE CASCADE,
  kind           text NOT NULL CHECK (kind IN ('File','Event')),
  title          text NOT NULL,
  on_date        date,
  stage_id       uuid REFERENCES stage(stage_id),
  status         text NOT NULL DEFAULT 'Open' CHECK (status IN ('Open','Closed','Approved')),
  source_room_id uuid REFERENCES room(room_id),           -- the room that is its source of truth
  by_person      uuid REFERENCES users(user_id),
  at             timestamptz NOT NULL DEFAULT clock_timestamp()
);

-- One chat per room; never used for answering. A message can point at a question ("mention a clause").
CREATE TABLE room_message (
  message_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id    uuid NOT NULL REFERENCES room(room_id) ON DELETE CASCADE,
  by_person  uuid NOT NULL REFERENCES users(user_id),
  body       text NOT NULL,
  mention_qr uuid,                                          -- a question run in this room
  at         timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE room_member (
  member_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id   uuid NOT NULL REFERENCES room(room_id) ON DELETE CASCADE,
  person_id uuid NOT NULL REFERENCES users(user_id),
  is_spoc   boolean NOT NULL DEFAULT false,
  UNIQUE (room_id, person_id)
);

CREATE TABLE seat (
  seat_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id    uuid NOT NULL REFERENCES run(run_id) ON DELETE CASCADE,
  stage_id  uuid NOT NULL REFERENCES stage(stage_id),
  seat      text NOT NULL CHECK (seat IN ('Doer','Reviewer','Approver','SPOC')),
  person_id uuid NOT NULL REFERENCES users(user_id),
  UNIQUE (run_id, stage_id, seat, person_id)
);

CREATE TABLE question_run (
  qr_id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id       uuid NOT NULL REFERENCES run(run_id) ON DELETE CASCADE,
  question_id  uuid NOT NULL REFERENCES question(question_id),
  room_id      uuid NOT NULL REFERENCES room(room_id),
  status       text NOT NULL DEFAULT 'Open' CHECK (status IN ('Open','Closed')),
  closed_as    text CHECK (closed_as IN ('Success','Dropped')),
  answer_state text NOT NULL DEFAULT 'Pending'
               CHECK (answer_state IN ('Pending','Submitted','Agreed','Contested','Deadlock','Cancelled')),
  answer       text,
  answer_data  jsonb,      -- the structured answer for the flow option
  source       text NOT NULL DEFAULT 'Person' CHECK (source IN ('Platform data','API','OCR','Person','Third party')),
  third_party  text,       -- who a third-party request went to, while it waits
  due_date     date,
  reopen_count integer NOT NULL DEFAULT 0,
  quadrant     text NOT NULL DEFAULT 'Do later' CHECK (quadrant IN ('Do now','Do later','Delegate','Delete'))  -- priority, at question level only
);

CREATE TABLE answer_round (
  round_id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  qr_id       uuid NOT NULL REFERENCES question_run(qr_id) ON DELETE CASCADE,
  kind        text NOT NULL CHECK (kind IN ('Submit','Review','Agree','Contest','Deadlock','Cancel','Reopen','Request')),
  body        text,
  data        jsonb,
  reason      text CHECK (reason IN ('Error found','Incomplete','Evidence missing','Disagree','Remove','Other')),
  explanation text,
  by_person   uuid NOT NULL REFERENCES users(user_id),
  at          timestamptz NOT NULL DEFAULT clock_timestamp()
);

-- Standalone: one person's task inside an entity. No rounds, no approver; only the owner marks it Done.
CREATE TABLE standalone_task (
  task_id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id        uuid NOT NULL REFERENCES users(user_id),
  company_user_id uuid NOT NULL REFERENCES users(user_id),
  title           text NOT NULL,
  notes           text,
  due_date        date,
  quadrant        text NOT NULL DEFAULT 'Do later' CHECK (quadrant IN ('Do now','Do later','Delegate','Delete')),
  status          text NOT NULL DEFAULT 'Open' CHECK (status IN ('Open','Done')),
  created_on      date NOT NULL DEFAULT current_date,
  done_at         timestamptz,
  fy              text
);

-- Call in and split: a document answered in an ER, called into our own PR or IR and split into lines
CREATE TABLE split_line (
  line_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_qr uuid NOT NULL REFERENCES question_run(qr_id) ON DELETE CASCADE,
  room_id   uuid NOT NULL REFERENCES room(room_id) ON DELETE CASCADE,
  seq       integer NOT NULL,
  text      text NOT NULL,
  state     text NOT NULL DEFAULT 'Agreed' CHECK (state IN ('Agreed','Under discussion')),
  note      text,
  by_person uuid REFERENCES users(user_id),
  at        timestamptz NOT NULL DEFAULT clock_timestamp()
);

-- Estimation vs Execution: line items with estimate and actuals; Borrowed lines carry the vendor invite chain
CREATE TABLE estimate_line (
  line_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id      uuid NOT NULL REFERENCES run(run_id) ON DELETE CASCADE,
  item        text NOT NULL,
  source      text NOT NULL CHECK (source IN ('Owned','Borrowed')),
  vendor_id   uuid REFERENCES users(user_id),
  vendor_name text,
  est_cost    numeric, est_price numeric, est_days numeric,
  act_cost    numeric, act_price numeric, act_days numeric,
  at          timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE audit_log (
  audit_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  at       timestamptz NOT NULL DEFAULT clock_timestamp(),
  run_id   uuid REFERENCES run(run_id) ON DELETE CASCADE,
  krama_id uuid REFERENCES krama(krama_id) ON DELETE CASCADE,
  task_id  uuid REFERENCES standalone_task(task_id) ON DELETE CASCADE,
  actor    uuid REFERENCES users(user_id),
  action   text NOT NULL,
  detail   text
);

-- ======================= Rules on masters =======================

CREATE FUNCTION user_type_of(u uuid) RETURNS text LANGUAGE sql STABLE AS
$$ SELECT user_type FROM users WHERE user_id = u $$;

CREATE FUNCTION user_name(u uuid) RETURNS text LANGUAGE sql STABLE AS
$$ SELECT name FROM users WHERE user_id = u $$;

-- Creating a company copies its type's standard Dept/BUs and role definitions
CREATE FUNCTION company_setup() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF user_type_of(NEW.user_id) IS DISTINCT FROM 'Company' THEN
    RAISE EXCEPTION 'A company record must point to a user of type Company';
  END IF;
  IF TG_OP = 'INSERT' THEN
    INSERT INTO dept_bu (company_user_id, name)
    SELECT NEW.user_id, name FROM company_type_dept_bu WHERE company_type_id = NEW.company_type_id;
    INSERT INTO role_definition (company_user_id, name, description)
    SELECT NEW.user_id, name, description FROM role_definition WHERE company_type_id = NEW.company_type_id;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER company_setup AFTER INSERT OR UPDATE ON company FOR EACH ROW EXECUTE FUNCTION company_setup();

CREATE FUNCTION link_check() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF user_type_of(NEW.person_id) IS DISTINCT FROM 'Individual' THEN
    RAISE EXCEPTION 'Only an Individual can be linked to an entity';
  END IF;
  IF user_type_of(NEW.company_user_id) IS DISTINCT FROM 'Company' THEN
    RAISE EXCEPTION 'The entity must be a user of type Company';
  END IF;
  IF NEW.dept_bu_id IS NOT NULL AND NOT EXISTS (
     SELECT 1 FROM dept_bu WHERE dept_bu_id = NEW.dept_bu_id AND company_user_id = NEW.company_user_id) THEN
    RAISE EXCEPTION 'Dept/BU must belong to the same entity';
  END IF;
  IF NEW.role_id IS NOT NULL AND NOT EXISTS (
     SELECT 1 FROM role_definition WHERE role_id = NEW.role_id AND company_user_id = NEW.company_user_id) THEN
    RAISE EXCEPTION 'Role must be one of this entity''s roles';
  END IF;
  -- a full-time employee elsewhere needs the employer's approval for any further link
  IF NOT NEW.is_full_time AND NOT NEW.employer_approved AND EXISTS (
     SELECT 1 FROM person_entity_link l WHERE l.person_id = NEW.person_id AND l.is_full_time
       AND l.company_user_id <> NEW.company_user_id) THEN
    RAISE EXCEPTION 'This person is a full-time employee of another entity; the employer''s approval is needed first';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER link_check BEFORE INSERT OR UPDATE ON person_entity_link FOR EACH ROW EXECUTE FUNCTION link_check();

CREATE FUNCTION user_expertise_check() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM unnest(NEW.expertise_ids) x WHERE x NOT IN (SELECT expertise_id FROM expertise)) THEN
    RAISE EXCEPTION 'Expertise must be picked from the Expertise master';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER user_expertise_check BEFORE INSERT OR UPDATE ON users FOR EACH ROW EXECUTE FUNCTION user_expertise_check();

-- ======================= Rules on Krama design =======================

CREATE FUNCTION path_rank(p text) RETURNS int LANGUAGE sql IMMUTABLE AS
$$ SELECT CASE p WHEN 'PR only' THEN 1 WHEN 'PR → IR' THEN 2 ELSE 3 END $$;

CREATE FUNCTION kind_rank(k text) RETURNS int LANGUAGE sql IMMUTABLE AS
$$ SELECT CASE k WHEN 'PR' THEN 1 WHEN 'IR' THEN 2 ELSE 3 END $$;

-- The Krama a design row belongs to
CREATE FUNCTION krama_of(p_table text, p_id uuid) RETURNS uuid LANGUAGE plpgsql STABLE AS $$
DECLARE k uuid;
BEGIN
  CASE p_table
    WHEN 'stage' THEN SELECT krama_id INTO k FROM stage WHERE stage_id = p_id;
    WHEN 'topic' THEN SELECT s.krama_id INTO k FROM topic t JOIN stage s USING (stage_id) WHERE t.topic_id = p_id;
    WHEN 'question' THEN SELECT s.krama_id INTO k FROM question q JOIN topic t USING (topic_id) JOIN stage s USING (stage_id) WHERE q.question_id = p_id;
    ELSE k := NULL;
  END CASE;
  RETURN k;
END $$;

-- A Published Krama is frozen (changes go into a new version); editing a Platform built copy
-- makes it Entity Customised; paths must stay within the stage's path.
CREATE FUNCTION design_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE k uuid; r record;
BEGIN
  IF TG_TABLE_NAME IN ('room_template','stage','report') THEN
    k := CASE WHEN TG_OP = 'DELETE' THEN OLD.krama_id ELSE NEW.krama_id END;
  ELSIF TG_TABLE_NAME = 'topic' THEN
    k := krama_of('stage', CASE WHEN TG_OP = 'DELETE' THEN OLD.stage_id ELSE NEW.stage_id END);
  ELSIF TG_TABLE_NAME = 'question' THEN
    k := krama_of('topic', CASE WHEN TG_OP = 'DELETE' THEN OLD.topic_id ELSE NEW.topic_id END);
  ELSIF TG_TABLE_NAME = 'question_link' THEN
    k := krama_of('question', CASE WHEN TG_OP = 'DELETE' THEN OLD.question_id ELSE NEW.question_id END);
  END IF;
  SELECT * INTO r FROM krama WHERE krama_id = k;
  IF r.status = 'Published' AND current_setting('demo.seeding', true) IS DISTINCT FROM 'on' THEN
    RAISE EXCEPTION 'A Published Krama is frozen; create a new version to change it';
  END IF;
  IF r.pool_mark = 'Platform built' AND current_setting('demo.seeding', true) IS DISTINCT FROM 'on' THEN
    UPDATE krama SET pool_mark = 'Entity Customised' WHERE krama_id = k;
  END IF;
  IF TG_OP <> 'DELETE' THEN
    IF TG_TABLE_NAME = 'topic' THEN
      IF path_rank(NEW.path) > path_rank((SELECT path FROM stage WHERE stage_id = NEW.stage_id)) THEN
        RAISE EXCEPTION 'A topic''s path cannot go beyond its stage''s path';
      END IF;
    ELSIF TG_TABLE_NAME = 'question' THEN
      IF kind_rank(NEW.ask_in) > path_rank((SELECT path FROM topic WHERE topic_id = NEW.topic_id)) THEN
        RAISE EXCEPTION 'A question can only be asked in a room on its topic''s path';
      END IF;
      -- allowed answer-type combinations: Decision, Input field or Checklist + File drop;
      -- Table grid or Compare box + Finding control (Signature panel always carries Version pin)
      IF NEW.also_needs = 'File drop' AND NEW.flow_option NOT IN ('Decision','Input field','Checklist') THEN
        RAISE EXCEPTION 'File drop can be added only to Decision, Input field or Checklist';
      END IF;
      IF NEW.also_needs = 'Finding control' AND NEW.flow_option NOT IN ('Table grid','Compare box') THEN
        RAISE EXCEPTION 'Finding control can be added only to Table grid or Compare box';
      END IF;
      IF NEW.flow_option IN ('Choice list','Checklist') AND coalesce(trim(NEW.setup_options), '') = '' THEN
        RAISE EXCEPTION '% needs its options listed, one per line', NEW.flow_option;
      END IF;
      IF NEW.flow_option = 'Table grid' AND coalesce(trim(NEW.setup_columns), '') = '' THEN
        RAISE EXCEPTION 'Table grid needs its columns listed, one per line';
      END IF;
    ELSIF TG_TABLE_NAME = 'question_link' THEN
      IF krama_of('question', NEW.predecessor_id) IS DISTINCT FROM k THEN
        RAISE EXCEPTION 'Linked questions must be in the same Krama';
      END IF;
      IF EXISTS (WITH RECURSIVE up(q) AS (
                   SELECT NEW.predecessor_id
                   UNION SELECT l.predecessor_id FROM question_link l JOIN up ON l.question_id = up.q)
                 SELECT 1 FROM up WHERE q = NEW.question_id) THEN
        RAISE EXCEPTION 'These links would form a cycle';
      END IF;
    END IF;
  END IF;
  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END $$;

CREATE TRIGGER g_room_template BEFORE INSERT OR UPDATE OR DELETE ON room_template FOR EACH ROW EXECUTE FUNCTION design_guard();
CREATE TRIGGER g_stage BEFORE INSERT OR UPDATE OR DELETE ON stage FOR EACH ROW EXECUTE FUNCTION design_guard();
CREATE TRIGGER g_topic BEFORE INSERT OR UPDATE OR DELETE ON topic FOR EACH ROW EXECUTE FUNCTION design_guard();
CREATE TRIGGER g_question BEFORE INSERT OR UPDATE OR DELETE ON question FOR EACH ROW EXECUTE FUNCTION design_guard();
CREATE TRIGGER g_question_link BEFORE INSERT OR UPDATE OR DELETE ON question_link FOR EACH ROW EXECUTE FUNCTION design_guard();
CREATE TRIGGER g_report BEFORE INSERT OR UPDATE OR DELETE ON report FOR EACH ROW EXECUTE FUNCTION design_guard();

-- A capability may only sit at a boundary it declares; a Published Krama is frozen
CREATE FUNCTION capability_use_check() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE c record; b text; k uuid; st text;
BEGIN
  IF TG_OP = 'DELETE' THEN
    SELECT status INTO st FROM krama WHERE krama_id = OLD.krama_id;
    IF st = 'Published' AND current_setting('demo.seeding', true) IS DISTINCT FROM 'on' THEN RAISE EXCEPTION 'A Published Krama is frozen; create a new version to change it'; END IF;
    RETURN OLD;
  END IF;
  SELECT * INTO c FROM capability WHERE code = NEW.code;
  b := CASE WHEN NEW.stage_id IS NOT NULL THEN 'stage' WHEN NEW.topic_id IS NOT NULL THEN 'topic' ELSE 'question' END;
  IF NOT b = ANY (c.boundaries) THEN RAISE EXCEPTION '% applies to % only', c.name, array_to_string(c.boundaries, ', '); END IF;
  k := COALESCE((SELECT krama_id FROM stage WHERE stage_id = NEW.stage_id), krama_of('stage', (SELECT stage_id FROM topic WHERE topic_id = NEW.topic_id)),
                krama_of('question', NEW.question_id));
  IF k IS DISTINCT FROM NEW.krama_id THEN RAISE EXCEPTION 'The capability must sit in the same Krama'; END IF;
  SELECT status INTO st FROM krama WHERE krama_id = NEW.krama_id;
  IF st = 'Published' AND current_setting('demo.seeding', true) IS DISTINCT FROM 'on' THEN RAISE EXCEPTION 'A Published Krama is frozen; create a new version to change it'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER capability_use_check BEFORE INSERT OR UPDATE OR DELETE ON capability_use FOR EACH ROW EXECUTE FUNCTION capability_use_check();

-- Entities cannot create Opportunity, Deal or Order management Kramas from scratch
CREATE FUNCTION krama_check() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.ownership_type = 'Entity Built Entity Owned'
     AND lower(coalesce(NEW.tag_domain, '')) IN ('opportunity','deal','order management') THEN
    RAISE EXCEPTION 'Opportunity, Deal and Order management Kramas can only be customised from platform built';
  END IF;
  IF NEW.owner_entity IS NULL AND NEW.ownership_type = 'Entity Built Entity Owned' THEN
    RAISE EXCEPTION 'An Entity Built Krama needs its owning entity';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER krama_check BEFORE INSERT OR UPDATE ON krama FOR EACH ROW EXECUTE FUNCTION krama_check();

-- Personal (Yousr) tasks: one person's own items, plus personal-identifier requests from an entity
CREATE TABLE personal_task (
  task_id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id     uuid NOT NULL REFERENCES users(user_id),
  kind         text NOT NULL DEFAULT 'Personal' CHECK (kind IN ('Personal','Identifier request')),
  requested_by uuid REFERENCES users(user_id),      -- the entity asking, for identifier requests
  title        text NOT NULL,
  purpose      text,
  due_date     date,
  quadrant     text NOT NULL DEFAULT 'Do later' CHECK (quadrant IN ('Do now','Do later','Delegate','Delete')),
  status       text NOT NULL DEFAULT 'To do' CHECK (status IN ('To do','Done','Deleted')),
  done_at      timestamptz
);


-- ---------- Dept/BU admin: one designated admin per Dept/BU ----------
ALTER TABLE person_entity_link ADD COLUMN is_dept_admin boolean NOT NULL DEFAULT false;
CREATE UNIQUE INDEX one_admin_per_dept_bu ON person_entity_link (dept_bu_id) WHERE is_dept_admin;

-- The Dept/BU a person administers in an entity (none if they are not a Dept/BU admin)
CREATE FUNCTION admin_dept(p uuid, e uuid) RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT dept_bu_id FROM person_entity_link WHERE person_id = p AND company_user_id = e AND is_dept_admin LIMIT 1
$$;
-- Catalogue: the entity admin edits every item; a Dept/BU admin adds items and edits their own Dept/BU's
CREATE FUNCTION can_edit_catalogue(p uuid, e uuid) RETURNS boolean LANGUAGE plpgsql STABLE AS $$
BEGIN RETURN is_entity_super(p, e) OR admin_dept(p, e) IS NOT NULL; END $$;
CREATE FUNCTION can_edit_item(p uuid, item uuid) RETURNS boolean LANGUAGE plpgsql STABLE AS $$
BEGIN
  RETURN (SELECT is_entity_super(p, ci.company_user_id) OR (ci.host_dept_bu_id IS NOT NULL AND ci.host_dept_bu_id = admin_dept(p, ci.company_user_id))
            FROM catalogue_item ci WHERE ci.item_id = item);
END $$;
