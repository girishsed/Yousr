-- Krama rules (FRD v3.0). Every action takes the acting person so rules are checked here.

-- ---------- who is who ----------

CREATE FUNCTION is_super(p uuid) RETURNS boolean LANGUAGE sql STABLE AS
$$ SELECT COALESCE((SELECT is_super_user FROM users WHERE user_id = p), false) $$;

CREATE FUNCTION is_entity_super(p uuid, e uuid) RETURNS boolean LANGUAGE sql STABLE AS
$$ SELECT EXISTS (SELECT 1 FROM person_entity_link WHERE person_id = p AND company_user_id = e AND is_entity_super_user) $$;

CREATE FUNCTION is_member_of_entity(p uuid, e uuid) RETURNS boolean LANGUAGE sql STABLE AS
$$ SELECT EXISTS (SELECT 1 FROM person_entity_link WHERE person_id = p AND company_user_id = e) $$;

-- Who may change a Krama's design: platform super-user for platform Kramas, the entity super-user for the entity's own
CREATE FUNCTION can_design(p uuid, k uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT CASE WHEN kr.owner_entity IS NULL THEN is_super(p) ELSE is_entity_super(p, kr.owner_entity) END
    FROM krama kr WHERE kr.krama_id = k
$$;

CREATE FUNCTION fy_label(d date) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT 'FY ' || (CASE WHEN extract(month FROM d) >= 4 THEN extract(year FROM d) ELSE extract(year FROM d) - 1 END)::int
         || '-' || lpad(((CASE WHEN extract(month FROM d) >= 4 THEN extract(year FROM d) ELSE extract(year FROM d) - 1 END)::int + 1 - 2000)::text, 2, '0')
$$;

CREATE FUNCTION log_run(r uuid, actor uuid, action text, detail text) RETURNS void LANGUAGE sql AS $$
  INSERT INTO audit_log (run_id, actor, action, detail) VALUES (r, actor, action, detail)
$$;

CREATE FUNCTION log_krama(k uuid, actor uuid, action text, detail text) RETURNS void LANGUAGE sql AS $$
  INSERT INTO audit_log (krama_id, actor, action, detail) VALUES (k, actor, action, detail)
$$;

-- ---------- Krama lifecycle (Create) ----------

-- Copy a Krama's whole design into a new Krama row
CREATE FUNCTION copy_krama(src uuid, p_owner uuid, p_ownership text, p_version int, p_prev uuid, p_source uuid)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE k uuid; s record; t record; q record; ns uuid; nt uuid;
BEGIN
  INSERT INTO krama (code, name, owner_entity, ownership_type, pool_mark, status, version, previous_version,
                     source_krama_id, tag_kind, tag_domain, lifetime_years)
  SELECT code, name, p_owner, p_ownership, NULL, 'Learning and Training', p_version, p_prev,
         p_source, tag_kind, tag_domain, lifetime_years
    FROM krama WHERE krama_id = src
  RETURNING krama_id INTO k;

  CREATE TEMP TABLE IF NOT EXISTS qmap (old uuid, new uuid) ON COMMIT DROP;
  DELETE FROM qmap;
  CREATE TEMP TABLE IF NOT EXISTS smap (old uuid, new uuid) ON COMMIT DROP;
  DELETE FROM smap;
  CREATE TEMP TABLE IF NOT EXISTS tmap (old uuid, new uuid) ON COMMIT DROP;
  DELETE FROM tmap;
  INSERT INTO room_template (krama_id, kind, label) SELECT k, kind, label FROM room_template WHERE krama_id = src;
  INSERT INTO report (krama_id, name, question_text) SELECT k, name, question_text FROM report WHERE krama_id = src;
  FOR s IN SELECT * FROM stage WHERE krama_id = src LOOP
    INSERT INTO stage (krama_id, name, seq, path) VALUES (k, s.name, s.seq, s.path) RETURNING stage_id INTO ns;
    INSERT INTO smap VALUES (s.stage_id, ns);
    INSERT INTO expertise_required (stage_id, expertise_id, mapped_as)
      SELECT ns, expertise_id, mapped_as FROM expertise_required WHERE stage_id = s.stage_id;
    FOR t IN SELECT * FROM topic WHERE stage_id = s.stage_id LOOP
      INSERT INTO topic (stage_id, name, seq, path, is_output) VALUES (ns, t.name, t.seq, t.path, t.is_output) RETURNING topic_id INTO nt;
      INSERT INTO tmap VALUES (t.topic_id, nt);
      INSERT INTO expertise_required (topic_id, expertise_id, mapped_as)
        SELECT nt, expertise_id, mapped_as FROM expertise_required WHERE topic_id = t.topic_id;
      FOR q IN SELECT * FROM question WHERE topic_id = t.topic_id LOOP
        WITH x AS (
          INSERT INTO question (topic_id, text, seq, flow_option, ask_in, rules, due_days,
                                setup_options, setup_choices, setup_multi, setup_columns, setup_limit, also_needs)
          VALUES (nt, q.text, q.seq, q.flow_option, q.ask_in, q.rules, q.due_days,
                  q.setup_options, q.setup_choices, q.setup_multi, q.setup_columns, q.setup_limit, q.also_needs) RETURNING question_id)
        INSERT INTO qmap SELECT q.question_id, x.question_id FROM x;
      END LOOP;
    END LOOP;
  END LOOP;
  INSERT INTO question_link (question_id, predecessor_id)
    SELECT a.new, b.new FROM question_link l JOIN qmap a ON a.old = l.question_id JOIN qmap b ON b.old = l.predecessor_id;
  INSERT INTO expertise_required (question_id, expertise_id, mapped_as)
    SELECT m.new, e.expertise_id, e.mapped_as FROM expertise_required e JOIN qmap m ON m.old = e.question_id;
  INSERT INTO capability_use (krama_id, code, stage_id, topic_id, question_id, note)
    SELECT k, cu.code, sm.new, tm.new, qm.new, cu.note FROM capability_use cu
      LEFT JOIN smap sm ON sm.old = cu.stage_id LEFT JOIN tmap tm ON tm.old = cu.topic_id LEFT JOIN qmap qm ON qm.old = cu.question_id
     WHERE cu.krama_id = src;
  RETURN k;
END $$;

-- Created → Learning and Training → Testing → Published (forward only)
CREATE FUNCTION set_krama_status(k uuid, actor uuid, p_status text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE r record; ranks text[] := ARRAY['Created','Learning and Training','Testing','Published'];
BEGIN
  SELECT * INTO r FROM krama WHERE krama_id = k;
  IF r IS NULL THEN RAISE EXCEPTION 'Krama not found'; END IF;
  IF NOT can_design(actor, k) THEN RAISE EXCEPTION 'You cannot change this Krama'; END IF;
  IF array_position(ranks, p_status) IS NULL OR array_position(ranks, p_status) <= array_position(ranks, r.status) THEN
    RAISE EXCEPTION 'A Krama only moves forward: Created → Learning and Training → Testing → Published';
  END IF;
  IF p_status = 'Published' THEN
    IF NOT EXISTS (SELECT 1 FROM stage WHERE krama_id = k) THEN RAISE EXCEPTION 'Add at least one stage before publishing'; END IF;
    IF EXISTS (SELECT 1 FROM stage s WHERE s.krama_id = k AND NOT EXISTS (SELECT 1 FROM topic t WHERE t.stage_id = s.stage_id))
      THEN RAISE EXCEPTION 'Every stage needs at least one topic'; END IF;
    IF EXISTS (SELECT 1 FROM topic t JOIN stage s USING (stage_id) WHERE s.krama_id = k
                 AND NOT EXISTS (SELECT 1 FROM question q WHERE q.topic_id = t.topic_id))
      THEN RAISE EXCEPTION 'Every topic needs at least one question'; END IF;
    IF EXISTS (SELECT 1 FROM stage WHERE krama_id = k AND trim(name) = '')
       OR EXISTS (SELECT 1 FROM topic t JOIN stage s USING (stage_id) WHERE s.krama_id = k AND trim(t.name) = '')
       OR EXISTS (SELECT 1 FROM question q JOIN topic t USING (topic_id) JOIN stage s USING (stage_id) WHERE s.krama_id = k AND trim(q.text) = '')
      THEN RAISE EXCEPTION 'A Krama cannot be published while any stage, topic or question is unnamed'; END IF;
    IF NOT EXISTS (SELECT 1 FROM report WHERE krama_id = k) THEN
      RAISE EXCEPTION 'Every workflow Krama needs at least one report before publishing';
    END IF;
    IF EXISTS (SELECT 1 FROM question q JOIN topic t USING (topic_id) JOIN stage s USING (stage_id)
                WHERE s.krama_id = k AND NOT EXISTS (SELECT 1 FROM room_template rt WHERE rt.krama_id = k AND rt.kind = q.ask_in))
      THEN RAISE EXCEPTION 'A question is asked in a room this Krama does not have'; END IF;
  END IF;
  UPDATE krama SET status = p_status WHERE krama_id = k;
  PERFORM log_krama(k, actor, 'Status ' || p_status, r.name || ' v' || r.version);
END $$;

-- A Published Krama is frozen; changes go into a new version
CREATE FUNCTION new_version(k uuid, actor uuid, p_what text) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE r record; nk uuid;
BEGIN
  SELECT * INTO r FROM krama WHERE krama_id = k;
  IF NOT can_design(actor, k) THEN RAISE EXCEPTION 'You cannot change this Krama'; END IF;
  IF r.status <> 'Published' THEN RAISE EXCEPTION 'Only a Published Krama gets a new version; edit this one directly'; END IF;
  IF EXISTS (SELECT 1 FROM krama WHERE previous_version = k) THEN RAISE EXCEPTION 'A newer version already exists'; END IF;
  nk := copy_krama(k, r.owner_entity, r.ownership_type, r.version + 1, k, r.source_krama_id);
  UPDATE krama SET pool_mark = r.pool_mark, what_changed = NULLIF(trim(p_what), '') WHERE krama_id = nk;
  IF to_regprocedure('copy_stage_context(uuid,uuid)') IS NOT NULL THEN EXECUTE 'SELECT copy_stage_context($1, $2)' USING k, nk; END IF;
  PERFORM log_krama(nk, actor, 'New version', r.name || ' v' || (r.version + 1));
  RETURN nk;
END $$;

-- An entity imports a Published platform Krama into its pool (Platform built until edited)
CREATE FUNCTION import_krama(src uuid, p_entity uuid, actor uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE r record; nk uuid;
BEGIN
  SELECT * INTO r FROM krama WHERE krama_id = src;
  IF r IS NULL OR r.owner_entity IS NOT NULL OR r.status <> 'Published' THEN
    RAISE EXCEPTION 'Only a Published platform Krama can be imported';
  END IF;
  IF r.ownership_type = 'Platform Built Platform Owned' THEN
    RAISE EXCEPTION 'Platform Built Platform Owned Kramas are used as they are; add them straight to the catalogue';
  END IF;
  IF NOT is_entity_super(actor, p_entity) THEN RAISE EXCEPTION 'Only the entity super-user can import into the pool'; END IF;
  nk := copy_krama(src, p_entity, 'Platform Built Entity Owned', 1, NULL, src);
  UPDATE krama SET pool_mark = 'Platform built' WHERE krama_id = nk;
  IF to_regprocedure('copy_stage_context(uuid,uuid)') IS NOT NULL THEN EXECUTE 'SELECT copy_stage_context($1, $2)' USING src, nk; END IF;
  PERFORM log_krama(nk, actor, 'Imported', r.name || ' v' || r.version || ' from the platform');
  RETURN nk;
END $$;

-- A newer Published platform version exists than the one this copy came from
CREATE FUNCTION newer_platform_version(k uuid) RETURNS integer LANGUAGE sql STABLE AS $$
  SELECT max(p.version) FROM krama c JOIN krama src ON src.krama_id = c.source_krama_id
    JOIN krama p ON p.code = src.code AND p.owner_entity IS NULL AND p.status = 'Published' AND p.version > src.version
   WHERE c.krama_id = k
$$;

-- ---------- Connect ----------

-- Share and assign a Published Krama to a catalogue item
CREATE FUNCTION assign_krama(p_item uuid, k uuid, actor uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE r record; it record;
BEGIN
  SELECT * INTO it FROM catalogue_item WHERE item_id = p_item;
  SELECT * INTO r FROM krama WHERE krama_id = k;
  IF it IS NULL THEN RAISE EXCEPTION 'Catalogue item not found'; END IF;
  IF r IS NULL OR r.status <> 'Published' THEN RAISE EXCEPTION 'Only a Published Krama can be assigned to a catalogue item'; END IF;
  IF NOT is_entity_super(actor, it.company_user_id) THEN RAISE EXCEPTION 'Only the entity super-user can assign Kramas'; END IF;
  IF NOT (r.owner_entity = it.company_user_id OR (r.owner_entity IS NULL AND r.ownership_type = 'Platform Built Platform Owned')) THEN
    RAISE EXCEPTION 'Import the Krama into your pool and publish it first';
  END IF;
  INSERT INTO catalogue_item_krama (item_id, krama_id) VALUES (p_item, k) ON CONFLICT DO NOTHING;
END $$;

-- ---------- persona types and the relationship matrix ----------

-- Is persona type p the same as, or narrower than, persona type a?
CREATE FUNCTION persona_within(p uuid, a uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
  WITH RECURSIVE up(id) AS (SELECT p UNION SELECT pt.parent_id FROM persona_type pt JOIN up ON pt.persona_type_id = up.id WHERE pt.parent_id IS NOT NULL)
  SELECT EXISTS (SELECT 1 FROM up WHERE id = a)
$$;

-- The platform Krama a copy came from (its matrix rows apply to the copy)
CREATE FUNCTION matrix_root(k uuid) RETURNS uuid LANGUAGE sql STABLE AS
$$ SELECT COALESCE((SELECT source_krama_id FROM krama WHERE krama_id = k), k) $$;

CREATE FUNCTION is_external(k uuid) RETURNS boolean LANGUAGE sql STABLE AS
$$ SELECT EXISTS (SELECT 1 FROM room_template WHERE krama_id = k AND kind = 'ER') $$;

-- Which of an item's Kramas apply: external ones only where the matrix maps them to the counterparty's
-- persona type (or a broader one) under the chosen relationship; internal ones under Department / Business Unit
CREATE FUNCTION resolve_kramas(p_item uuid, p_relationship text, p_counterparty uuid) RETURNS SETOF uuid LANGUAGE sql STABLE AS $$
  SELECT ck.krama_id FROM catalogue_item_krama ck
   WHERE ck.item_id = p_item AND (
     (NOT is_external(ck.krama_id) AND p_relationship IN ('Department','Business Unit'))
     OR (is_external(ck.krama_id) AND p_counterparty IS NOT NULL AND EXISTS (
          SELECT 1 FROM krama_relationship m
           WHERE m.krama_id IN (ck.krama_id, matrix_root(ck.krama_id))
             AND m.relationship = p_relationship AND m.party_type = 'Entity'
             AND persona_within((SELECT persona_type_id FROM company WHERE user_id = p_counterparty), m.persona_type_id))))
$$;

-- ---------- Conduct ----------

-- Selecting a catalogue item activates a run: Instance ID, rooms, one question run per question
-- Starting from a catalogue item: pick the relationship (and counterparty); the Krama comes from the matrix
CREATE FUNCTION activate(p_item uuid, actor uuid, p_counterparty uuid, p_relationship text, p_krama uuid)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE it record; rid uuid; code text; k uuid; n int;
BEGIN
  SELECT * INTO it FROM catalogue_item WHERE item_id = p_item;
  IF it IS NULL THEN RAISE EXCEPTION 'Catalogue item not found'; END IF;
  IF NOT is_member_of_entity(actor, it.company_user_id) THEN RAISE EXCEPTION 'Only members of this entity can start it'; END IF;
  IF p_relationship IS NULL THEN RAISE EXCEPTION 'Choose the relationship'; END IF;
  IF p_relationship NOT IN ('Department','Business Unit') AND p_counterparty IS NULL THEN
    RAISE EXCEPTION 'Choose who this is with';
  END IF;
  IF p_counterparty IS NOT NULL AND user_type_of(p_counterparty) IS DISTINCT FROM 'Company' THEN
    RAISE EXCEPTION 'The counterparty must be an entity';
  END IF;
  SELECT count(*) INTO n FROM resolve_kramas(p_item, p_relationship, p_counterparty);
  IF n = 0 THEN RAISE EXCEPTION 'No Krama of this item is mapped to this counterparty''s persona type as %', p_relationship; END IF;
  IF p_krama IS NOT NULL THEN
    IF p_krama NOT IN (SELECT resolve_kramas(p_item, p_relationship, p_counterparty)) THEN
      RAISE EXCEPTION 'That Krama does not apply to this counterparty';
    END IF;
    k := p_krama;
  ELSIF n = 1 THEN
    SELECT x INTO k FROM resolve_kramas(p_item, p_relationship, p_counterparty) x;
  ELSE
    RAISE EXCEPTION 'More than one Krama applies; choose one';
  END IF;
  code := 'INS-' || lpad(nextval('instance_seq')::text, 4, '0');
  INSERT INTO run (instance_code, item_id, krama_id, company_user_id, counterparty, relationship, requestor_id, fy)
  VALUES (code, p_item, k, it.company_user_id, p_counterparty, p_relationship, actor, fy_label(current_date))
  RETURNING run_id INTO rid;
  INSERT INTO room (run_id, kind, name, with_entity)
  SELECT rid, kind, label, CASE WHEN kind = 'ER' THEN p_counterparty END FROM room_template WHERE krama_id = k;
  INSERT INTO room_member (room_id, person_id, is_spoc) SELECT room_id, actor, true FROM room WHERE run_id = rid;
  -- every topic is Retained in each room its path allows
  INSERT INTO room_topic (room_id, topic_id)
  SELECT rm.room_id, t.topic_id FROM room rm JOIN topic t ON true JOIN stage s ON s.stage_id = t.stage_id
   WHERE rm.run_id = rid AND s.krama_id = k AND kind_rank(rm.kind) <= path_rank(t.path);
  -- one registry per room to start with
  INSERT INTO registry (room_id, name, description, holds)
  SELECT room_id, 'Files and events', 'Everything filed or scheduled in this room.', 'Both' FROM room WHERE run_id = rid;
  INSERT INTO question_run (run_id, question_id, room_id, due_date)
  SELECT rid, q.question_id, rm.room_id, current_date + q.due_days
    FROM question q JOIN topic t USING (topic_id) JOIN stage s USING (stage_id)
    JOIN room rm ON rm.run_id = rid AND rm.kind = q.ask_in
   WHERE s.krama_id = k;
  PERFORM log_run(rid, actor, 'Activated', it.name || ' as ' || code || COALESCE(' with ' || user_name(p_counterparty) || ' (' || p_relationship || ')', ''));
  RETURN rid;
END $$;

-- Seat a named person per stage. Own side joins the rooms on the stage's path; the counterparty joins the ER only.
CREATE FUNCTION seat_person(p_run uuid, p_stage uuid, p_seat text, p_person uuid, actor uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE r record; st record; counter boolean;
BEGIN
  SELECT * INTO r FROM run WHERE run_id = p_run;
  IF r IS NULL THEN RAISE EXCEPTION 'Run not found'; END IF;
  IF r.requestor_id <> actor AND NOT is_super(actor) THEN RAISE EXCEPTION 'Only the Requestor/Conductor seats people'; END IF;
  IF r.locked_at IS NOT NULL THEN RAISE EXCEPTION 'This run is conserved; amend it first'; END IF;
  SELECT * INTO st FROM stage WHERE stage_id = p_stage AND krama_id = r.krama_id;
  IF st IS NULL THEN RAISE EXCEPTION 'Stage is not part of this run'; END IF;
  IF user_type_of(p_person) IS DISTINCT FROM 'Individual' THEN RAISE EXCEPTION 'Only a person can take a seat'; END IF;
  -- someone who belongs to both entities sits on this entity's side
  counter := r.counterparty IS NOT NULL AND is_member_of_entity(p_person, r.counterparty)
             AND NOT is_member_of_entity(p_person, r.company_user_id);
  IF NOT counter AND NOT is_member_of_entity(p_person, r.company_user_id) THEN
    RAISE EXCEPTION 'The person must belong to this entity or the counterparty';
  END IF;
  IF counter AND path_rank(st.path) < 3 THEN
    RAISE EXCEPTION 'This stage never reaches the external room, so the counterparty cannot be seated in it';
  END IF;
  INSERT INTO seat (run_id, stage_id, seat, person_id) VALUES (p_run, p_stage, p_seat, p_person) ON CONFLICT DO NOTHING;
  INSERT INTO room_member (room_id, person_id, is_spoc)
  SELECT rm.room_id, p_person, p_seat = 'SPOC' FROM room rm
   WHERE rm.run_id = p_run AND rm.parent_room_id IS NULL
     AND ((counter AND rm.kind = 'ER') OR (NOT counter AND kind_rank(rm.kind) <= path_rank(st.path)))
  ON CONFLICT (room_id, person_id) DO UPDATE SET is_spoc = room_member.is_spoc OR EXCLUDED.is_spoc;
  PERFORM log_run(p_run, actor, 'Seated', user_name(p_person) || ' as ' || p_seat || ' for ' || st.name);
END $$;

CREATE FUNCTION unseat(p_seat uuid, actor uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE s record;
BEGIN
  SELECT seat.*, run.requestor_id, stage.name AS stage_name FROM seat JOIN run USING (run_id) JOIN stage USING (stage_id)
   WHERE seat_id = p_seat INTO s;
  IF s IS NULL THEN RAISE EXCEPTION 'Seat not found'; END IF;
  IF s.requestor_id <> actor AND NOT is_super(actor) THEN RAISE EXCEPTION 'Only the Requestor/Conductor changes seats'; END IF;
  DELETE FROM seat WHERE seat_id = p_seat;
  PERFORM log_run(s.run_id, actor, 'Unseated', user_name(s.person_id) || ' as ' || s.seat || ' for ' || s.stage_name);
END $$;

-- ---------- visibility ----------

CREATE FUNCTION my_rooms(actor uuid) RETURNS SETOF uuid LANGUAGE sql STABLE AS
$$ SELECT room_id FROM room_member WHERE person_id = actor $$;

CREATE FUNCTION visible_runs(actor uuid) RETURNS SETOF uuid LANGUAGE sql STABLE AS $$
  SELECT run_id FROM run WHERE is_super(actor)
  UNION SELECT rm.run_id FROM room rm WHERE rm.room_id IN (SELECT my_rooms(actor))
$$;

-- The room is the boundary: you see a question in your room; once agreed it travels to every room on its topic's path
-- The room is the boundary: you see a question in its own room; once agreed it travels to every room that
-- retains its topic. A child ER whose permission is still Requested shows nothing.
CREATE FUNCTION can_see_qr(qr uuid, actor uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT is_super(actor) OR EXISTS (
    SELECT 1 FROM question_run x JOIN question q USING (question_id)
      JOIN room rm ON rm.run_id = x.run_id AND rm.permission <> 'Requested'
     WHERE x.qr_id = qr AND rm.room_id IN (SELECT my_rooms(actor))
       AND (rm.room_id = x.room_id
            OR (x.answer_state = 'Agreed' AND EXISTS (SELECT 1 FROM room_topic rt WHERE rt.room_id = rm.room_id AND rt.topic_id = q.topic_id))))
$$;

-- ---------- answering ----------

CREATE FUNCTION qr_ctx(qr uuid) RETURNS TABLE (run_id uuid, stage_id uuid, room_id uuid, status text, answer_state text, locked boolean)
LANGUAGE sql STABLE AS $$
  SELECT x.run_id, t.stage_id, x.room_id, x.status, x.answer_state,
         EXISTS (SELECT 1 FROM question_link l JOIN question_run p ON p.run_id = x.run_id AND p.question_id = l.predecessor_id
                  WHERE l.question_id = x.question_id AND NOT (p.status = 'Closed' AND COALESCE(p.closed_as, 'Success') = 'Success'))
         -- Stage gate: a gated earlier stage must close before this stage opens
         OR EXISTS (SELECT 1 FROM capability_use cu JOIN stage gs ON gs.stage_id = cu.stage_id JOIN stage me ON me.stage_id = t.stage_id
                     WHERE cu.code = 'stage_gate' AND gs.krama_id = me.krama_id AND gs.seq < me.seq
                       AND EXISTS (SELECT 1 FROM question_run y JOIN question qy ON qy.question_id = y.question_id JOIN topic ty ON ty.topic_id = qy.topic_id
                                    WHERE y.run_id = x.run_id AND ty.stage_id = gs.stage_id
                                      AND NOT (y.status = 'Closed' AND COALESCE(y.closed_as, 'Success') = 'Success')))
    FROM question_run x JOIN question q USING (question_id) JOIN topic t USING (topic_id)
   WHERE x.qr_id = qr
$$;

CREATE FUNCTION has_seat(p_run uuid, p_stage uuid, p uuid, p_seats text[]) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT EXISTS (SELECT 1 FROM seat WHERE run_id = p_run AND stage_id = p_stage AND person_id = p AND seat = ANY (p_seats))
$$;

CREATE FUNCTION in_room(p_room uuid, p uuid) RETURNS boolean LANGUAGE sql STABLE AS
$$ SELECT EXISTS (SELECT 1 FROM room_member WHERE room_id = p_room AND person_id = p) $$;

CREATE FUNCTION last_submitter(qr uuid) RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT by_person FROM answer_round WHERE qr_id = qr AND kind = 'Submit' ORDER BY at DESC LIMIT 1
$$;

-- Whose turn it is on a question: Doer while Pending or Contested; Reviewer while a seated Reviewer
-- has not yet reviewed the latest answer; then Approver / SPOC. Nobody once closed, waiting, or conserved.
CREATE FUNCTION is_with(qr uuid, actor uuid) RETURNS boolean LANGUAGE plpgsql STABLE AS $$
DECLARE c record; lk timestamptz; reviewer_pending boolean;
BEGIN
  SELECT * INTO c FROM qr_ctx(qr);
  IF c.run_id IS NULL OR c.status <> 'Open' OR c.locked THEN RETURN false; END IF;
  SELECT locked_at INTO lk FROM run WHERE run_id = c.run_id;
  IF lk IS NOT NULL THEN RETURN false; END IF;
  IF c.answer_state IN ('Pending','Contested') THEN
    RETURN has_seat(c.run_id, c.stage_id, actor, ARRAY['Doer']);
  END IF;
  IF c.answer_state <> 'Submitted' OR last_submitter(qr) = actor THEN RETURN false; END IF;
  reviewer_pending := EXISTS (SELECT 1 FROM seat WHERE run_id = c.run_id AND stage_id = c.stage_id AND seat = 'Reviewer')
    AND NOT EXISTS (SELECT 1 FROM answer_round WHERE qr_id = qr AND kind = 'Review'
                      AND at > (SELECT max(at) FROM answer_round WHERE qr_id = qr AND kind = 'Submit'));
  IF reviewer_pending THEN
    RETURN has_seat(c.run_id, c.stage_id, actor, ARRAY['Reviewer']);
  END IF;
  RETURN has_seat(c.run_id, c.stage_id, actor, ARRAY['Approver','SPOC']);
END $$;

CREATE FUNCTION assert_can_act(qr uuid, actor uuid, p_seats text[]) RETURNS void LANGUAGE plpgsql AS $$
DECLARE c record; lk timestamptz;
BEGIN
  SELECT * INTO c FROM qr_ctx(qr);
  IF c.run_id IS NULL THEN RAISE EXCEPTION 'Question not found'; END IF;
  SELECT locked_at INTO lk FROM run WHERE run_id = c.run_id;
  IF lk IS NOT NULL THEN RAISE EXCEPTION 'This run is conserved; amend it first'; END IF;
  IF c.status <> 'Open' THEN RAISE EXCEPTION 'This question is closed'; END IF;
  IF c.locked THEN RAISE EXCEPTION 'This question waits for its linked questions to close as Success'; END IF;
  IF NOT in_room(c.room_id, actor) THEN RAISE EXCEPTION 'You are not seated in this question''s room'; END IF;
  IF NOT has_seat(c.run_id, c.stage_id, actor, p_seats) THEN
    RAISE EXCEPTION 'Only the % seated on this stage can do this', array_to_string(p_seats, ' or ');
  END IF;
END $$;

-- Close the run when every question is closed; it then locks and is conserved under its FY
CREATE FUNCTION check_run(p_run uuid, actor uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE res text;
BEGIN
  IF EXISTS (SELECT 1 FROM question_run WHERE run_id = p_run AND status = 'Open') THEN RETURN; END IF;
  res := CASE WHEN EXISTS (SELECT 1 FROM question_run WHERE run_id = p_run AND closed_as = 'Dropped')
              THEN 'Unfulfilled' ELSE 'Fulfilled' END;
  UPDATE run SET status = 'Closed', result = res, locked_at = clock_timestamp() WHERE run_id = p_run;
  PERFORM log_run(p_run, NULL, 'Run ' || res, 'Locked and conserved under ' || (SELECT fy FROM run WHERE run_id = p_run));
END $$;

-- Checks a structured answer against its question's flow option. A NULL answer (demo seed only) skips the check.
CREATE FUNCTION check_answer(q question, d jsonb) RETURNS void LANGUAGE plpgsql AS $$
DECLARE opts text[]; ch text[]; item text; r jsonb; v jsonb; diff numeric;
BEGIN
  IF d IS NULL THEN RETURN; END IF;
  opts := array_remove(string_to_array(coalesce(q.setup_options, ''), E'\n'), '');
  CASE q.flow_option
  WHEN 'Decision' THEN
    IF coalesce(trim(d->>'text'), '') = '' THEN RAISE EXCEPTION 'Write the answer'; END IF;
  WHEN 'Input field' THEN
    IF coalesce(trim(d->>'value'), '') = '' THEN RAISE EXCEPTION 'This field is required'; END IF;
  WHEN 'Choice list' THEN
    IF jsonb_array_length(coalesce(d->'picked', '[]')) = 0 THEN RAISE EXCEPTION 'Pick an option'; END IF;
    IF NOT q.setup_multi AND jsonb_array_length(d->'picked') > 1 THEN RAISE EXCEPTION 'Pick only one option'; END IF;
    FOR v IN SELECT * FROM jsonb_array_elements(d->'picked') LOOP
      IF NOT (v #>> '{}') = ANY (opts) THEN RAISE EXCEPTION 'Pick from the listed options'; END IF;
    END LOOP;
  WHEN 'Checklist' THEN
    ch := array_remove(string_to_array(coalesce(nullif(q.setup_choices, ''), E'Yes\nNo\nNot applicable'), E'\n'), '');
    FOREACH item IN ARRAY opts LOOP
      IF coalesce(d->'items'->>item, '') = '' THEN RAISE EXCEPTION 'Every item needs a choice: %', item; END IF;
      IF NOT (d->'items'->>item) = ANY (ch) THEN RAISE EXCEPTION 'Pick a listed choice for %', item; END IF;
    END LOOP;
  WHEN 'File drop' THEN
    IF coalesce(trim(d->>'file'), '') = '' THEN RAISE EXCEPTION 'Add the file'; END IF;
    IF coalesce(d->>'mobility', '') NOT IN ('Mobile','Fixed') THEN RAISE EXCEPTION 'Mark the file Mobile or Fixed'; END IF;
  WHEN 'Assign' THEN
    IF coalesce(trim(d->>'note'), '') = '' THEN RAISE EXCEPTION 'Add a note on what was done'; END IF;
  WHEN 'Table grid' THEN
    IF jsonb_array_length(coalesce(d->'rows', '[]')) = 0 THEN RAISE EXCEPTION 'Add at least one row'; END IF;
    FOR r IN SELECT * FROM jsonb_array_elements(d->'rows') LOOP
      IF coalesce(r->>'check', '') NOT IN ('Checked','Matched','Clear','Flagged') THEN RAISE EXCEPTION 'Mark every row Checked, Matched, Clear or Flagged'; END IF;
      IF r->>'check' = 'Flagged' AND (coalesce(trim(r->>'explanation'), '') = '' OR coalesce(trim(r->>'evidence'), '') = '') THEN
        RAISE EXCEPTION 'A Flagged row needs an explanation and evidence';
      END IF;
    END LOOP;
  WHEN 'Compare box' THEN
    IF (d->>'a') IS NULL OR (d->>'b') IS NULL THEN RAISE EXCEPTION 'Enter both values'; END IF;
    diff := abs((d->>'a')::numeric - (d->>'b')::numeric);
    IF q.setup_limit IS NOT NULL AND diff > q.setup_limit AND coalesce(trim(d->>'explanation'), '') = '' THEN
      RAISE EXCEPTION 'The difference is outside the limit: explain it';
    END IF;
  WHEN 'Finding control' THEN
    IF coalesce(d->>'finding', '') NOT IN ('Clear','Flagged') THEN RAISE EXCEPTION 'Mark it Clear or Flagged'; END IF;
    IF d->>'finding' = 'Flagged' AND (coalesce(trim(d->>'explanation'), '') = '' OR coalesce(trim(d->>'evidence'), '') = '') THEN
      RAISE EXCEPTION 'Flagged needs an explanation and evidence';
    END IF;
  WHEN 'Signature panel' THEN
    IF coalesce(trim(d->>'version'), '') = '' THEN RAISE EXCEPTION 'Name the version being signed; it locks on signing'; END IF;
    IF coalesce((d->>'signed')::boolean, false) IS NOT TRUE THEN RAISE EXCEPTION 'Sign to submit'; END IF;
  ELSE NULL;
  END CASE;
  IF q.also_needs = 'File drop' AND d ? 'attachment' AND coalesce(trim(d->'attachment'->>'file'), '') <> ''
     AND coalesce(d->'attachment'->>'mobility', '') NOT IN ('Mobile','Fixed') THEN
    RAISE EXCEPTION 'Mark the attached file Mobile or Fixed';
  END IF;
  IF q.also_needs = 'Finding control' THEN
    IF coalesce(d->>'finding', '') NOT IN ('Clear','Flagged') THEN RAISE EXCEPTION 'Add the finding: Clear or Flagged'; END IF;
    IF d->>'finding' = 'Flagged' AND coalesce(trim(d->>'explanation'), '') = '' THEN RAISE EXCEPTION 'A Flagged finding needs an explanation'; END IF;
  END IF;
END $$;

CREATE FUNCTION submit_answer(qr uuid, actor uuid, p_answer text, p_source text, p_data jsonb DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $$
DECLARE c record; q question;
BEGIN
  PERFORM assert_can_act(qr, actor, ARRAY['Doer']);
  SELECT * INTO c FROM qr_ctx(qr);
  IF c.answer_state NOT IN ('Pending','Contested') THEN RAISE EXCEPTION 'This question is not waiting for an answer'; END IF;
  IF coalesce(trim(p_answer), '') = '' THEN RAISE EXCEPTION 'Answer is required'; END IF;
  SELECT question.* INTO q FROM question JOIN question_run USING (question_id) WHERE qr_id = qr;
  PERFORM check_answer(q, p_data);
  UPDATE question_run SET answer = p_answer, answer_data = p_data, answer_state = 'Submitted', source = COALESCE(p_source, 'Person') WHERE qr_id = qr;
  INSERT INTO answer_round (qr_id, kind, body, data, by_person) VALUES (qr, 'Submit', p_answer, p_data, actor);
  PERFORM log_run(c.run_id, actor, 'Submitted', p_answer);
END $$;

-- A Remove round: if the side that answered agrees to remove it, the question ends Cancelled
CREATE FUNCTION accept_removal(qr uuid, actor uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE c record; last record;
BEGIN
  PERFORM assert_can_act(qr, actor, ARRAY['Doer']);
  SELECT * INTO c FROM qr_ctx(qr);
  SELECT * INTO last FROM answer_round WHERE qr_id = qr ORDER BY at DESC LIMIT 1;
  IF c.answer_state <> 'Contested' OR last.kind <> 'Contest' OR last.reason IS DISTINCT FROM 'Remove' THEN
    RAISE EXCEPTION 'There is no request to remove this question';
  END IF;
  UPDATE question_run SET answer_state = 'Cancelled', status = 'Closed', closed_as = NULL WHERE qr_id = qr;
  INSERT INTO answer_round (qr_id, kind, explanation, by_person) VALUES (qr, 'Cancel', 'Removal agreed: ' || coalesce(last.explanation, ''), actor);
  PERFORM log_run(c.run_id, actor, 'Cancelled', 'Removal agreed');
  PERFORM check_run(c.run_id, actor);
END $$;

-- Maker-checker: the Reviewer checks before the answer can be agreed
CREATE FUNCTION review_answer(qr uuid, actor uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE c record;
BEGIN
  PERFORM assert_can_act(qr, actor, ARRAY['Reviewer']);
  SELECT * INTO c FROM qr_ctx(qr);
  IF c.answer_state <> 'Submitted' THEN RAISE EXCEPTION 'Only a submitted answer can be reviewed'; END IF;
  IF last_submitter(qr) = actor THEN RAISE EXCEPTION 'The person who answered cannot review it'; END IF;
  INSERT INTO answer_round (qr_id, kind, by_person) VALUES (qr, 'Review', actor);
  PERFORM log_run(c.run_id, actor, 'Reviewed', NULL);
END $$;

CREATE FUNCTION agree_answer(qr uuid, actor uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE c record;
BEGIN
  PERFORM assert_can_act(qr, actor, ARRAY['Approver','SPOC']);
  SELECT * INTO c FROM qr_ctx(qr);
  IF c.answer_state <> 'Submitted' THEN RAISE EXCEPTION 'Only a submitted answer can be agreed'; END IF;
  IF last_submitter(qr) = actor THEN RAISE EXCEPTION 'The person who answered cannot agree their own answer'; END IF;
  IF EXISTS (SELECT 1 FROM seat WHERE run_id = c.run_id AND stage_id = c.stage_id AND seat = 'Reviewer')
     AND NOT EXISTS (SELECT 1 FROM answer_round WHERE qr_id = qr AND kind = 'Review'
                       AND at > (SELECT max(at) FROM answer_round WHERE qr_id = qr AND kind = 'Submit')) THEN
    RAISE EXCEPTION 'The Reviewer must check this answer first';
  END IF;
  -- Maker-checker: a second person must review before it is agreed
  IF EXISTS (SELECT 1 FROM capability_use cu JOIN question q ON q.question_id = (SELECT question_id FROM question_run WHERE qr_id = qr)
              WHERE cu.code = 'maker_checker' AND (cu.question_id = q.question_id OR cu.topic_id = q.topic_id))
     AND NOT EXISTS (SELECT 1 FROM answer_round WHERE qr_id = qr AND kind = 'Review'
                       AND at > (SELECT max(at) FROM answer_round WHERE qr_id = qr AND kind = 'Submit')) THEN
    RAISE EXCEPTION 'Maker-checker: a Reviewer must check this answer before it is agreed';
  END IF;
  UPDATE question_run SET answer_state = 'Agreed', status = 'Closed', closed_as = 'Success' WHERE qr_id = qr;
  INSERT INTO answer_round (qr_id, kind, by_person) VALUES (qr, 'Agree', actor);
  PERFORM log_run(c.run_id, actor, 'Agreed', (SELECT answer FROM question_run WHERE qr_id = qr));
  PERFORM check_run(c.run_id, actor);
END $$;

CREATE FUNCTION contest_answer(qr uuid, actor uuid, p_reason text, p_expl text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE c record;
BEGIN
  PERFORM assert_can_act(qr, actor, ARRAY['Approver','Reviewer','SPOC']);
  SELECT * INTO c FROM qr_ctx(qr);
  IF c.answer_state <> 'Submitted' THEN RAISE EXCEPTION 'Only a submitted answer can be contested'; END IF;
  IF last_submitter(qr) = actor THEN RAISE EXCEPTION 'The person who answered cannot contest their own answer'; END IF;
  IF p_reason IS NULL THEN RAISE EXCEPTION 'Choose a reason'; END IF;
  IF coalesce(trim(p_expl), '') = '' THEN RAISE EXCEPTION 'Add an explanation'; END IF;
  UPDATE question_run SET answer_state = 'Contested' WHERE qr_id = qr;
  INSERT INTO answer_round (qr_id, kind, reason, explanation, by_person) VALUES (qr, 'Contest', p_reason, p_expl, actor);
  PERFORM log_run(c.run_id, actor, 'Contested', p_reason || ': ' || p_expl);
END $$;

CREATE FUNCTION deadlock_answer(qr uuid, actor uuid, p_expl text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE c record;
BEGIN
  PERFORM assert_can_act(qr, actor, ARRAY['Approver','SPOC']);
  SELECT * INTO c FROM qr_ctx(qr);
  IF c.answer_state NOT IN ('Submitted','Contested') THEN RAISE EXCEPTION 'Deadlock is declared on an answer in discussion'; END IF;
  IF coalesce(trim(p_expl), '') = '' THEN RAISE EXCEPTION 'Add both views in the explanation'; END IF;
  UPDATE question_run SET answer_state = 'Deadlock', status = 'Closed', closed_as = 'Dropped' WHERE qr_id = qr;
  INSERT INTO answer_round (qr_id, kind, explanation, by_person) VALUES (qr, 'Deadlock', p_expl, actor);
  PERFORM log_run(c.run_id, actor, 'Deadlock (Dropped)', p_expl);
  PERFORM check_run(c.run_id, actor);
END $$;

-- Cancelled ends a question that is no longer needed (not a failure)
CREATE FUNCTION cancel_question(qr uuid, actor uuid, p_expl text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE c record; req uuid;
BEGIN
  SELECT * INTO c FROM qr_ctx(qr);
  SELECT requestor_id INTO req FROM run WHERE run_id = c.run_id;
  IF c.status <> 'Open' THEN RAISE EXCEPTION 'This question is closed'; END IF;
  IF actor <> req AND NOT has_seat(c.run_id, c.stage_id, actor, ARRAY['Approver']) THEN
    RAISE EXCEPTION 'Only the Requestor/Conductor or the Approver can cancel a question';
  END IF;
  IF coalesce(trim(p_expl), '') = '' THEN RAISE EXCEPTION 'Say why it is no longer needed'; END IF;
  UPDATE question_run SET answer_state = 'Cancelled', status = 'Closed', closed_as = NULL WHERE qr_id = qr;
  INSERT INTO answer_round (qr_id, kind, explanation, by_person) VALUES (qr, 'Cancel', p_expl, actor);
  PERFORM log_run(c.run_id, actor, 'Cancelled', p_expl);
  PERFORM check_run(c.run_id, actor);
END $$;

-- Only Success can be reopened; Dropped is final
CREATE FUNCTION reopen_question(qr uuid, actor uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE x record; r record;
BEGIN
  SELECT * INTO x FROM question_run WHERE qr_id = qr;
  SELECT * INTO r FROM run WHERE run_id = x.run_id;
  IF r.requestor_id <> actor THEN RAISE EXCEPTION 'Only the Requestor/Conductor can reopen'; END IF;
  IF r.locked_at IS NOT NULL THEN RAISE EXCEPTION 'This run is conserved; amend it first'; END IF;
  IF NOT (x.status = 'Closed' AND x.closed_as = 'Success') THEN
    RAISE EXCEPTION 'Only a question closed as Success can be reopened; Dropped is final';
  END IF;
  UPDATE question_run SET status = 'Open', closed_as = NULL, answer_state = 'Pending', reopen_count = reopen_count + 1 WHERE qr_id = qr;
  INSERT INTO answer_round (qr_id, kind, by_person) VALUES (qr, 'Reopen', actor);
  PERFORM log_run(x.run_id, actor, 'Reopened', NULL);
END $$;

-- Amending a conserved run brings it back to Conduct as INS-xxxx · A1, A2
CREATE FUNCTION amend_run(p_run uuid, actor uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE r record;
BEGIN
  SELECT * INTO r FROM run WHERE run_id = p_run;
  IF r.requestor_id <> actor THEN RAISE EXCEPTION 'Only the Requestor/Conductor can amend'; END IF;
  IF r.locked_at IS NULL THEN RAISE EXCEPTION 'Only a conserved run can be amended'; END IF;
  UPDATE run SET amendment_no = amendment_no + 1, status = 'Open', result = NULL, locked_at = NULL WHERE run_id = p_run;
  PERFORM log_run(p_run, actor, 'Amended', r.instance_code || ' · A' || (r.amendment_no + 1));
END $$;

-- The Krama a design row belongs to, for permission checks on plain edits
CREATE FUNCTION design_krama(p_key text, p_row json) RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT CASE p_key
    WHEN 'krama' THEN (p_row->>'krama_id')::uuid
    WHEN 'room-template' THEN (p_row->>'krama_id')::uuid
    WHEN 'stage' THEN (p_row->>'krama_id')::uuid
    WHEN 'report' THEN (p_row->>'krama_id')::uuid
    WHEN 'topic' THEN krama_of('stage', (p_row->>'stage_id')::uuid)
    WHEN 'question' THEN krama_of('topic', (p_row->>'topic_id')::uuid)
    WHEN 'question-link' THEN krama_of('question', (p_row->>'question_id')::uuid)
    WHEN 'krama-relationship' THEN (p_row->>'krama_id')::uuid
    WHEN 'expertise-required' THEN COALESCE(krama_of('stage', (p_row->>'stage_id')::uuid),
                                            krama_of('topic', (p_row->>'topic_id')::uuid),
                                            krama_of('question', (p_row->>'question_id')::uuid))
  END
$$;

-- ---------- Standalone (one person; closes only when the owner marks it Done) ----------

CREATE FUNCTION create_standalone(actor uuid, p_entity uuid, p_title text, p_notes text, p_due date, p_quadrant text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE t uuid;
BEGIN
  IF NOT is_member_of_entity(actor, p_entity) THEN RAISE EXCEPTION 'You can only create Standalone tasks in your own entity'; END IF;
  IF coalesce(trim(p_title), '') = '' THEN RAISE EXCEPTION 'Title is required'; END IF;
  INSERT INTO standalone_task (owner_id, company_user_id, title, notes, due_date, quadrant)
  VALUES (actor, p_entity, trim(p_title), NULLIF(trim(p_notes), ''), p_due, COALESCE(p_quadrant, 'Do later'))
  RETURNING task_id INTO t;
  INSERT INTO audit_log (task_id, actor, action, detail) VALUES (t, actor, 'Standalone created', trim(p_title));
  RETURN t;
END $$;

CREATE FUNCTION update_standalone(p_task uuid, actor uuid, p_title text, p_notes text, p_due date, p_quadrant text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE r record;
BEGIN
  SELECT * INTO r FROM standalone_task WHERE task_id = p_task;
  IF r IS NULL OR r.owner_id <> actor THEN RAISE EXCEPTION 'Only the owner can change a Standalone task'; END IF;
  IF r.status = 'Done' THEN RAISE EXCEPTION 'This task is done and conserved'; END IF;
  IF coalesce(trim(p_title), '') = '' THEN RAISE EXCEPTION 'Title is required'; END IF;
  UPDATE standalone_task SET title = trim(p_title), notes = NULLIF(trim(p_notes), ''), due_date = p_due,
         quadrant = COALESCE(p_quadrant, quadrant) WHERE task_id = p_task;
  INSERT INTO audit_log (task_id, actor, action, detail) VALUES (p_task, actor, 'Standalone changed', trim(p_title));
END $$;

CREATE FUNCTION mark_done(p_task uuid, actor uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE r record;
BEGIN
  SELECT * INTO r FROM standalone_task WHERE task_id = p_task;
  IF r IS NULL OR r.owner_id <> actor THEN RAISE EXCEPTION 'Only the owner can mark a Standalone task Done'; END IF;
  IF r.status = 'Done' THEN RAISE EXCEPTION 'Already done'; END IF;
  UPDATE standalone_task SET status = 'Done', done_at = clock_timestamp(), fy = fy_label(current_date) WHERE task_id = p_task;
  INSERT INTO audit_log (task_id, actor, action, detail) VALUES (p_task, actor, 'Standalone done', r.title || ' — conserved under ' || fy_label(current_date));
END $$;

-- ---------- Catalogue (entity data): add an item, then edit it section by section ----------

CREATE FUNCTION jtext(b jsonb, k text) RETURNS text LANGUAGE sql IMMUTABLE AS $$ SELECT NULLIF(trim(b->>k), '') $$;
CREATE FUNCTION juuids(b jsonb, k text) RETURNS uuid[] LANGUAGE sql IMMUTABLE AS
$$ SELECT COALESCE(array_agg(x::uuid), '{}') FROM jsonb_array_elements_text(COALESCE(b->k, '[]')) x WHERE x <> '' $$;

-- e buys from v (Vendor or Pre-vendor)
CREATE FUNCTION is_vendor_of(v uuid, e uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT EXISTS (SELECT 1 FROM run WHERE company_user_id = e AND counterparty = v AND relationship IN ('Pre-vendor','Vendor'))
$$;

-- A vendor's published sell-side item reaches entity e as Borrowed: Generic to all its clients, or Customised naming e
CREATE FUNCTION borrowed_by(ci catalogue_item, e uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT ci.review = 'Success' AND ci.visibility_scope = 'External' AND ci.visibility_audience = 'Client'
     AND (ci.visibility_reach = 'Generic' OR e = ANY (ci.visibility_names)) AND is_vendor_of(ci.company_user_id, e)
$$;

CREATE FUNCTION can_see_item(actor uuid, ci catalogue_item) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT is_member_of_entity(actor, ci.company_user_id)
      OR EXISTS (SELECT 1 FROM person_entity_link l WHERE l.person_id = actor AND borrowed_by(ci, l.company_user_id))
$$;

CREATE FUNCTION visibility_label(ci catalogue_item) RETURNS text LANGUAGE sql STABLE AS $$
  SELECT CASE
    WHEN ci.visibility_scope IS NULL THEN 'Not set'
    WHEN ci.visibility_audience = 'Self' THEN 'Internal · Self'
    WHEN ci.visibility_scope = 'Internal' THEN 'Internal · ' || COALESCE((SELECT name FROM dept_bu WHERE dept_bu_id = ci.host_dept_bu_id), 'no host') || ' → '
         || CASE WHEN ci.visibility_reach = 'Customised'
                 THEN (SELECT string_agg(name, ', ' ORDER BY name) FROM dept_bu WHERE dept_bu_id = ANY (ci.visibility_names))
                 ELSE 'All Dept/BUs' END
    WHEN ci.visibility_audience = 'Discover and Connect' THEN 'Discover and Connect'
    ELSE ci.visibility_audience || ' · ' || COALESCE(ci.visibility_reach, 'Generic') END
$$;

CREATE FUNCTION assert_item_editor(p_item uuid, actor uuid) RETURNS catalogue_item LANGUAGE plpgsql AS $$
DECLARE it catalogue_item;
BEGIN
  SELECT * INTO it FROM catalogue_item WHERE item_id = p_item;
  IF it IS NULL THEN RAISE EXCEPTION 'Catalogue item not found'; END IF;
  IF NOT can_edit_item(actor, it.item_id) THEN RAISE EXCEPTION 'Only the entity admin, or the admin of this item''s Dept/BU, can change it'; END IF;
  RETURN it;
END $$;

-- Add item: Compliance or Business › Process → Domain → Domain persona; Business › Commercial can instead take a library item
-- as it is or customised. It starts in Alpha, unpublished, with one variant.
CREATE FUNCTION create_catalogue_item(p_entity uuid, actor uuid, b jsonb) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE cat text := jtext(b, 'catalogue'); dp uuid := jtext(b, 'domain_persona_id')::uuid; lib library_item;
        use text := jtext(b, 'library_use'); nm text := jtext(b, 'name'); typ text := COALESCE(jtext(b, 'item_type'), 'Services'); i uuid;
BEGIN
  IF NOT can_edit_catalogue(actor, p_entity) THEN RAISE EXCEPTION 'Only the entity admin or a Dept/BU admin can add catalogue items'; END IF;
  IF cat IS NULL OR cat NOT IN ('Compliance','Process','Commercial') THEN RAISE EXCEPTION 'Choose the catalogue: Compliance, Process or Commercial'; END IF;
  IF jtext(b, 'library_item_id') IS NOT NULL THEN
    IF cat <> 'Commercial' THEN RAISE EXCEPTION 'Library items are picked in Business › Commercial only'; END IF;
    SELECT * INTO lib FROM library_item WHERE library_item_id = jtext(b, 'library_item_id')::uuid;
    IF lib IS NULL THEN RAISE EXCEPTION 'Library item not found'; END IF;
    use := COALESCE(use, 'As it is');
    IF use = 'As it is' THEN nm := lib.name; END IF;
    nm := COALESCE(nm, lib.name); typ := lib.kind; dp := COALESCE(dp, lib.domain_persona_id);
  ELSE
    use := NULL;
  END IF;
  IF dp IS NULL THEN RAISE EXCEPTION 'Choose the Domain persona'; END IF;
  IF (SELECT d.catalogue FROM domain_persona p JOIN catalogue_domain d USING (domain_id) WHERE p.domain_persona_id = dp) IS DISTINCT FROM cat THEN
    RAISE EXCEPTION 'That Domain persona belongs to another catalogue';
  END IF;
  IF nm IS NULL THEN RAISE EXCEPTION 'Name is required'; END IF;
  IF typ NOT IN ('SKU','SDU','Services') THEN RAISE EXCEPTION 'Item type is SKU, SDU or Services'; END IF;
  INSERT INTO catalogue_item (company_user_id, name, item_type, catalogue, domain_persona_id, library_item_id, library_use, content_title)
  VALUES (p_entity, nm, typ, cat, dp, lib.library_item_id, use, nm) RETURNING item_id INTO i;
  IF NOT is_entity_super(actor, p_entity) THEN UPDATE catalogue_item SET host_dept_bu_id = admin_dept(actor, p_entity) WHERE item_id = i; END IF;
  INSERT INTO catalogue_variant (item_id, name) VALUES (i, CASE typ WHEN 'SKU' THEN 'Standard pack' WHEN 'SDU' THEN 'Standard unit' ELSE 'Standard' END);
  RETURN i;
END $$;

-- An entity instance of a catalogue item, with its first Krama assigned (used by the Krama console)
CREATE FUNCTION add_catalogue_item(k uuid, p_entity uuid, actor uuid, p_name text) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE r record; i uuid;
BEGIN
  SELECT * INTO r FROM krama WHERE krama_id = k;
  IF NOT can_edit_catalogue(actor, p_entity) THEN RAISE EXCEPTION 'Only the entity admin or a Dept/BU admin can add catalogue items'; END IF;
  INSERT INTO catalogue_item (company_user_id, name, content_title, catalogue)
  VALUES (p_entity, COALESCE(NULLIF(trim(p_name), ''), r.name), COALESCE(NULLIF(trim(p_name), ''), r.name),
          CASE WHEN r.tag_kind = 'Compliance' THEN 'Compliance' ELSE 'Process' END)
  RETURNING item_id INTO i;
  INSERT INTO catalogue_variant (item_id, name) VALUES (i, 'Standard');
  PERFORM assign_krama(i, k, actor);
  RETURN i;
END $$;

-- One section of the item page at a time; returns the id of anything it created
CREATE FUNCTION save_catalogue_section(p_item uuid, actor uuid, p_section text, b jsonb) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE it catalogue_item := assert_item_editor(p_item, actor); v catalogue_variant; x uuid; s text; n int;
BEGIN
  CASE p_section
  WHEN 'overview' THEN
    IF jtext(b, 'name') IS NULL THEN RAISE EXCEPTION 'Name is required'; END IF;
    IF it.library_use = 'As it is' AND jtext(b, 'name') <> it.name THEN
      RAISE EXCEPTION 'This item uses the library item as it is; choose Customise to rename it';
    END IF;
    UPDATE catalogue_item SET name = jtext(b, 'name') WHERE item_id = p_item;

  WHEN 'customise' THEN
    IF it.library_item_id IS NULL THEN RAISE EXCEPTION 'Only items taken from the library can be customised'; END IF;
    UPDATE catalogue_item SET library_use = 'Customised' WHERE item_id = p_item;

  WHEN 'visibility' THEN
    s := jtext(b, 'scope');
    IF s IS NULL OR s NOT IN ('External','Internal') THEN RAISE EXCEPTION 'Choose External or Internal'; END IF;
    IF s = 'External' AND jtext(b, 'audience') NOT IN ('Discover and Connect','Client','Vendor') THEN RAISE EXCEPTION 'Choose Discover and Connect, Client or Vendor'; END IF;
    IF s = 'Internal' AND jtext(b, 'audience') NOT IN ('Internal client','Self') THEN RAISE EXCEPTION 'Choose Internal client or Self'; END IF;
    IF s = 'Internal' AND (jtext(b, 'host_dept_bu_id') IS NULL OR NOT EXISTS (
         SELECT 1 FROM dept_bu WHERE dept_bu_id = jtext(b, 'host_dept_bu_id')::uuid AND company_user_id = it.company_user_id)) THEN
      RAISE EXCEPTION 'Choose the Host: the one Dept/BU that owns it';
    END IF;
    IF jtext(b, 'audience') IN ('Client','Vendor','Internal client') AND jtext(b, 'reach') = 'Customised' AND cardinality(juuids(b, 'names')) = 0 THEN
      RAISE EXCEPTION 'Customised needs at least one name';
    END IF;
    IF s = 'External' AND EXISTS (SELECT 1 FROM unnest(juuids(b, 'names')) u WHERE user_type_of(u) IS DISTINCT FROM 'Company' OR u = it.company_user_id) THEN
      RAISE EXCEPTION 'Customised names must be other entities';
    END IF;
    IF s = 'Internal' AND EXISTS (SELECT 1 FROM unnest(juuids(b, 'names')) u
                                   WHERE NOT EXISTS (SELECT 1 FROM dept_bu WHERE dept_bu_id = u AND company_user_id = it.company_user_id)) THEN
      RAISE EXCEPTION 'Internal clients must be this entity''s Dept/BUs';
    END IF;
    UPDATE catalogue_item SET visibility_scope = s, visibility_audience = jtext(b, 'audience'),
           visibility_reach = CASE WHEN jtext(b, 'audience') IN ('Client','Vendor','Internal client') THEN COALESCE(jtext(b, 'reach'), 'Generic') END,
           visibility_names = CASE WHEN jtext(b, 'reach') = 'Customised' AND jtext(b, 'audience') IN ('Client','Vendor','Internal client') THEN juuids(b, 'names') ELSE '{}' END,
           host_dept_bu_id = CASE WHEN s = 'Internal' THEN jtext(b, 'host_dept_bu_id')::uuid END
     WHERE item_id = p_item;

  WHEN 'variant' THEN
    IF jtext(b, 'name') IS NULL THEN RAISE EXCEPTION 'Variant name is required'; END IF;
    IF jtext(b, 'offer_kind') IS NOT NULL AND (b->>'offer_amount') IS NULL THEN RAISE EXCEPTION 'Say how much the offer is'; END IF;
    IF jtext(b, 'offer_kind') = '%' AND (b->>'offer_amount')::numeric > 100 THEN RAISE EXCEPTION 'A percentage offer cannot exceed 100'; END IF;
    IF jtext(b, 'offer_for') = 'Named clients' AND cardinality(juuids(b, 'offer_names')) = 0 THEN RAISE EXCEPTION 'Name at least one client for the offer'; END IF;
    IF jtext(b, 'variant_id') IS NULL THEN
      SELECT * INTO v FROM catalogue_variant WHERE variant_id = jtext(b, 'copy_from')::uuid AND item_id = p_item;
      INSERT INTO catalogue_variant (item_id, name, seq, pricing_type, price, tax_mode, hsn_sac, gst_rate, quotation_wording, invoice_wording, promo)
      VALUES (p_item, jtext(b, 'name'), COALESCE((SELECT max(seq) + 1 FROM catalogue_variant WHERE item_id = p_item), 1),
              COALESCE(v.pricing_type, 'Fixed'), v.price, COALESCE(v.tax_mode, '+ tax'), v.hsn_sac, v.gst_rate, v.quotation_wording, v.invoice_wording, v.promo)
      RETURNING variant_id INTO x;
      IF v.variant_id IS NOT NULL THEN
        INSERT INTO catalogue_journey_step (variant_id, step, krama_id) SELECT x, step, krama_id FROM catalogue_journey_step WHERE variant_id = v.variant_id;
        INSERT INTO catalogue_dependency (variant_id, level, krama_id, dep_item_id, timing, done_outside)
        SELECT x, level, krama_id, dep_item_id, timing, done_outside FROM catalogue_dependency WHERE variant_id = v.variant_id;
      END IF;
      RETURN x;
    END IF;
    UPDATE catalogue_variant SET name = jtext(b, 'name'), pricing_type = COALESCE(jtext(b, 'pricing_type'), 'Fixed'),
           price = CASE WHEN jtext(b, 'pricing_type') = 'Request quote' THEN NULL ELSE (b->>'price')::numeric END,
           tax_mode = COALESCE(jtext(b, 'tax_mode'), '+ tax'), hsn_sac = jtext(b, 'hsn_sac'), gst_rate = (b->>'gst_rate')::numeric,
           quotation_wording = jtext(b, 'quotation_wording'), invoice_wording = jtext(b, 'invoice_wording'),
           offer_kind = jtext(b, 'offer_kind'), offer_amount = CASE WHEN jtext(b, 'offer_kind') IS NULL THEN NULL ELSE (b->>'offer_amount')::numeric END,
           offer_for = COALESCE(jtext(b, 'offer_for'), 'Everyone'),
           offer_names = CASE WHEN jtext(b, 'offer_for') = 'Named clients' THEN juuids(b, 'offer_names') ELSE '{}' END,
           offer_until = jtext(b, 'offer_until')::date, promo = jtext(b, 'promo')
     WHERE variant_id = jtext(b, 'variant_id')::uuid AND item_id = p_item;
    IF NOT FOUND THEN RAISE EXCEPTION 'Variant not found'; END IF;

  WHEN 'variant-remove' THEN
    SELECT count(*) INTO n FROM catalogue_variant WHERE item_id = p_item;
    IF n <= 1 THEN RAISE EXCEPTION 'An item keeps at least one variant'; END IF;
    DELETE FROM catalogue_variant WHERE variant_id = jtext(b, 'variant_id')::uuid AND item_id = p_item;

  WHEN 'content' THEN
    IF jsonb_typeof(COALESCE(b->'blocks', '[]')) <> 'array' THEN RAISE EXCEPTION 'Content blocks must be a list'; END IF;
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(b->'blocks', '[]')) e WHERE e->>'kind' NOT IN ('Text','Image','Video')) THEN
      RAISE EXCEPTION 'A block is text, image or video';
    END IF;
    UPDATE catalogue_item SET content_title = jtext(b, 'title'), main_image = jtext(b, 'main_image'),
           content_blocks = COALESCE((SELECT jsonb_agg(e) FROM jsonb_array_elements(COALESCE(b->'blocks', '[]')) e WHERE NULLIF(trim(e->>'body'), '') IS NOT NULL), '[]')
     WHERE item_id = p_item;

  WHEN 'marketing' THEN
    UPDATE catalogue_item SET brand_name = jtext(b, 'brand_name'), category = jtext(b, 'category'), sub_category = jtext(b, 'sub_category'),
           competitors = COALESCE((SELECT jsonb_agg(e) FROM jsonb_array_elements(COALESCE(b->'competitors', '[]')) e
                                    WHERE NULLIF(trim(e->>'brand'), '') IS NOT NULL OR NULLIF(trim(e->>'business'), '') IS NOT NULL), '[]')
     WHERE item_id = p_item;

  WHEN 'landing-external' THEN
    IF jtext(b, 'url') IS NULL OR jtext(b, 'url') !~ '^https?://' THEN RAISE EXCEPTION 'Enter the page address, starting with https://'; END IF;
    UPDATE catalogue_item SET landing_page = jtext(b, 'url'), landing_status = 'External page' WHERE item_id = p_item;

  WHEN 'landing-generate' THEN
    UPDATE catalogue_item SET landing_page = NULL, landing_status = 'Generated' WHERE item_id = p_item;

  WHEN 'landing-approve' THEN
    IF it.landing_status IS DISTINCT FROM 'Generated' THEN RAISE EXCEPTION 'Generate a landing page first'; END IF;
    UPDATE catalogue_item SET landing_status = 'Approved',
           landing_page = 'https://' || lower(regexp_replace(user_name(it.company_user_id), '[^A-Za-z0-9]+', '-', 'g')) || '.compane.site/' || lower(it.catalogue_code)
     WHERE item_id = p_item;

  WHEN 'journey' THEN
    SELECT * INTO v FROM catalogue_variant WHERE variant_id = jtext(b, 'variant_id')::uuid AND item_id = p_item;
    IF v IS NULL THEN RAISE EXCEPTION 'Variant not found'; END IF;
    IF jtext(b, 'step') NOT IN ('Opportunity','Deal','Order management','Process') THEN RAISE EXCEPTION 'Unknown journey step'; END IF;
    IF jtext(b, 'krama_id') IS NULL THEN
      DELETE FROM catalogue_journey_step WHERE variant_id = v.variant_id AND step = jtext(b, 'step');
    ELSE
      IF NOT EXISTS (SELECT 1 FROM krama WHERE krama_id = jtext(b, 'krama_id')::uuid AND status = 'Published'
                       AND (owner_entity = it.company_user_id OR (owner_entity IS NULL AND ownership_type = 'Platform Built Platform Owned'))) THEN
        RAISE EXCEPTION 'Pick a Published Krama from your pool';
      END IF;
      INSERT INTO catalogue_journey_step (variant_id, step, krama_id) VALUES (v.variant_id, jtext(b, 'step'), jtext(b, 'krama_id')::uuid)
      ON CONFLICT (variant_id, step) DO UPDATE SET krama_id = EXCLUDED.krama_id;
    END IF;

  WHEN 'dependency' THEN
    SELECT * INTO v FROM catalogue_variant WHERE variant_id = jtext(b, 'variant_id')::uuid AND item_id = p_item;
    IF v IS NULL THEN RAISE EXCEPTION 'Variant not found'; END IF;
    IF jtext(b, 'timing') NOT IN ('Before','After') THEN RAISE EXCEPTION 'Choose Before or After'; END IF;
    IF jtext(b, 'level') = 'Krama' THEN
      IF NOT EXISTS (SELECT 1 FROM krama WHERE krama_id = jtext(b, 'ref_id')::uuid AND status = 'Published') THEN RAISE EXCEPTION 'Pick a Published Krama'; END IF;
      INSERT INTO catalogue_dependency (variant_id, level, krama_id, timing, done_outside)
      VALUES (v.variant_id, 'Krama', jtext(b, 'ref_id')::uuid, jtext(b, 'timing'), COALESCE((b->>'done_outside')::boolean, false)) RETURNING dependency_id INTO x;
    ELSIF jtext(b, 'level') = 'Catalogue' THEN
      IF jtext(b, 'ref_id')::uuid = p_item THEN RAISE EXCEPTION 'An item cannot depend on itself'; END IF;
      IF NOT EXISTS (SELECT 1 FROM catalogue_item WHERE item_id = jtext(b, 'ref_id')::uuid AND company_user_id = it.company_user_id
                       AND release IN ('Beta','General Availability')) THEN
        RAISE EXCEPTION 'Only Beta and General Availability items can be picked';
      END IF;
      INSERT INTO catalogue_dependency (variant_id, level, dep_item_id, timing, done_outside)
      VALUES (v.variant_id, 'Catalogue', jtext(b, 'ref_id')::uuid, jtext(b, 'timing'), COALESCE((b->>'done_outside')::boolean, false)) RETURNING dependency_id INTO x;
    ELSE
      RAISE EXCEPTION 'Choose Krama level or catalogue level';
    END IF;
    RETURN x;

  WHEN 'dependency-outside' THEN
    UPDATE catalogue_dependency d SET done_outside = COALESCE((b->>'done_outside')::boolean, false)
      FROM catalogue_variant v WHERE d.dependency_id = jtext(b, 'dependency_id')::uuid AND v.variant_id = d.variant_id AND v.item_id = p_item;

  WHEN 'dependency-remove' THEN
    DELETE FROM catalogue_dependency d USING catalogue_variant v
     WHERE d.dependency_id = jtext(b, 'dependency_id')::uuid AND v.variant_id = d.variant_id AND v.item_id = p_item;

  WHEN 'seat' THEN
    s := jtext(b, 'seat');
    IF s NOT IN ('Buyer','Seller','Fulfiller','Assurer','Representation') THEN RAISE EXCEPTION 'Unknown seat'; END IF;
    IF jtext(b, 'side') = 'Internal' THEN
      IF NOT EXISTS (SELECT 1 FROM dept_bu WHERE dept_bu_id = jtext(b, 'ref_id')::uuid AND company_user_id = it.company_user_id) THEN
        RAISE EXCEPTION 'Choose one of this entity''s Dept/BUs';
      END IF;
    ELSIF jtext(b, 'side') = 'External' THEN
      IF user_type_of(jtext(b, 'ref_id')::uuid) IS DISTINCT FROM 'Company' OR jtext(b, 'ref_id')::uuid = it.company_user_id THEN
        RAISE EXCEPTION 'Choose a client or vendor entity by name';
      END IF;
    ELSE
      RAISE EXCEPTION 'Choose Internal or External';
    END IF;
    -- The Assurer is never the Fulfiller on the same item
    IF s IN ('Assurer','Fulfiller') AND EXISTS (SELECT 1 FROM catalogue_seat WHERE item_id = p_item
         AND seat = CASE s WHEN 'Assurer' THEN 'Fulfiller' ELSE 'Assurer' END AND coalesce(dept_bu_id, party_id) = jtext(b, 'ref_id')::uuid) THEN
      RAISE EXCEPTION 'The Assurer is never the Fulfiller on the same item';
    END IF;
    IF s = 'Fulfiller' THEN
      -- Ownership: the entity (one Dept/BU) or vendors; several vendors make a quote comparison
      IF jtext(b, 'side') = 'Internal' OR EXISTS (SELECT 1 FROM catalogue_seat WHERE item_id = p_item AND seat = 'Fulfiller' AND side = 'Internal') THEN
        DELETE FROM catalogue_seat WHERE item_id = p_item AND seat = 'Fulfiller';
      END IF;
      IF jtext(b, 'vendor_item_id') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM catalogue_item WHERE item_id = jtext(b, 'vendor_item_id')::uuid
                                                                   AND company_user_id = jtext(b, 'ref_id')::uuid) THEN
        RAISE EXCEPTION 'The mapped item must be from that vendor''s catalogue';
      END IF;
    ELSE
      DELETE FROM catalogue_seat WHERE item_id = p_item AND seat = s;
    END IF;
    INSERT INTO catalogue_seat (item_id, seat, side, dept_bu_id, party_id, vendor_item_id)
    VALUES (p_item, s, jtext(b, 'side'),
            CASE WHEN jtext(b, 'side') = 'Internal' THEN jtext(b, 'ref_id')::uuid END,
            CASE WHEN jtext(b, 'side') = 'External' THEN jtext(b, 'ref_id')::uuid END,
            CASE WHEN s = 'Fulfiller' AND jtext(b, 'side') = 'External' THEN jtext(b, 'vendor_item_id')::uuid END)
    ON CONFLICT DO NOTHING RETURNING catalogue_seat_id INTO x;
    RETURN x;

  WHEN 'seat-remove' THEN
    DELETE FROM catalogue_seat WHERE catalogue_seat_id = jtext(b, 'catalogue_seat_id')::uuid AND item_id = p_item;

  -- Kramas the item runs: any Published Krama in the entity's pool, also one already on another item
  WHEN 'krama-assign' THEN
    PERFORM assign_krama(p_item, jtext(b, 'krama_id')::uuid, actor);
  WHEN 'krama-remove' THEN
    -- Runs already started keep their Krama; only new starts stop offering it
    DELETE FROM catalogue_item_krama WHERE item_id = p_item AND krama_id = jtext(b, 'krama_id')::uuid;
    IF NOT FOUND THEN RAISE EXCEPTION 'That Krama is not on this item'; END IF;

  WHEN 'release' THEN
    IF jtext(b, 'release') NOT IN ('Alpha','Pilot','Beta','General Availability') THEN RAISE EXCEPTION 'Release is Alpha, Pilot, Beta or General Availability'; END IF;
    UPDATE catalogue_item SET release = jtext(b, 'release') WHERE item_id = p_item;

  -- Share and Assign: the review; only Success publishes the item
  WHEN 'share' THEN
    IF it.visibility_scope IS NULL THEN RAISE EXCEPTION 'Set who sees the item (Visibility) before sharing it for review'; END IF;
    UPDATE catalogue_item SET review = 'In review' WHERE item_id = p_item;
  WHEN 'review-success' THEN
    IF it.review <> 'In review' THEN RAISE EXCEPTION 'The item is not in review'; END IF;
    UPDATE catalogue_item SET review = 'Success' WHERE item_id = p_item;
  WHEN 'review-back' THEN
    UPDATE catalogue_item SET review = 'Not shared' WHERE item_id = p_item;

  ELSE
    RAISE EXCEPTION 'Unknown section %', p_section;
  END CASE;
  RETURN NULL;
END $$;

-- Priority (quadrant) sits at question level; anyone seated in the question's room, or the Requestor/Conductor, can move it
CREATE FUNCTION set_quadrant(qr uuid, actor uuid, p_quadrant text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE x record; r record;
BEGIN
  SELECT * INTO x FROM question_run WHERE qr_id = qr;
  IF x IS NULL THEN RAISE EXCEPTION 'Question not found'; END IF;
  SELECT * INTO r FROM run WHERE run_id = x.run_id;
  IF NOT (in_room(x.room_id, actor) OR r.requestor_id = actor) THEN RAISE EXCEPTION 'You are not seated in this question''s room'; END IF;
  IF p_quadrant NOT IN ('Do now','Do later','Delegate','Delete') THEN RAISE EXCEPTION 'Unknown quadrant'; END IF;
  UPDATE question_run SET quadrant = p_quadrant WHERE qr_id = qr;
  PERFORM log_run(x.run_id, actor, 'Priority', (SELECT text FROM question WHERE question_id = x.question_id) || ': ' || p_quadrant);
END $$;

-- ---------- Personal (Yousr) tasks: only the owner sees and acts on them ----------
CREATE FUNCTION personal_task_act(p_task uuid, actor uuid, p_action text, p_title text, p_due date, p_quadrant text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE r record; t uuid;
BEGIN
  IF p_action = 'create' THEN
    IF coalesce(trim(p_title), '') = '' THEN RAISE EXCEPTION 'Title is required'; END IF;
    INSERT INTO personal_task (owner_id, title, due_date, quadrant) VALUES (actor, trim(p_title), p_due, COALESCE(p_quadrant, 'Do later'))
    RETURNING task_id INTO t;
    RETURN t;
  END IF;
  SELECT * INTO r FROM personal_task WHERE task_id = p_task;
  IF r IS NULL OR r.owner_id <> actor THEN RAISE EXCEPTION 'Only you can change your own tasks'; END IF;
  IF p_action = 'done' THEN
    IF r.kind <> 'Personal' THEN RAISE EXCEPTION 'Give consent to close a request'; END IF;
    UPDATE personal_task SET status = 'Done', done_at = clock_timestamp() WHERE task_id = p_task;
  ELSIF p_action = 'consent' THEN
    IF r.kind <> 'Identifier request' THEN RAISE EXCEPTION 'Only a request needs consent'; END IF;
    UPDATE personal_task SET status = 'Done', done_at = clock_timestamp() WHERE task_id = p_task;
  ELSIF p_action = 'delete' THEN
    IF r.kind <> 'Personal' THEN RAISE EXCEPTION 'A request from an entity cannot be deleted'; END IF;
    UPDATE personal_task SET status = 'Deleted' WHERE task_id = p_task;
  ELSIF p_action = 'restore' THEN
    UPDATE personal_task SET status = 'To do', done_at = NULL WHERE task_id = p_task AND status = 'Deleted';
  ELSIF p_action = 'quadrant' THEN
    UPDATE personal_task SET quadrant = p_quadrant WHERE task_id = p_task;
  ELSE
    RAISE EXCEPTION 'Unknown action';
  END IF;
  RETURN p_task;
END $$;


-- ---------- Phase 2: more rooms, child rooms, retaining topics, registries, room chat ----------

CREATE FUNCTION add_room(p_run uuid, actor uuid, p_kind text, p_name text, p_with uuid, p_parent uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE r record; par record; rid uuid; par_with uuid; par_name text;
BEGIN
  SELECT * INTO r FROM run WHERE run_id = p_run;
  IF r.requestor_id <> actor THEN RAISE EXCEPTION 'Only the Requestor/Conductor adds rooms'; END IF;
  IF r.locked_at IS NOT NULL THEN RAISE EXCEPTION 'This run is conserved; amend it first'; END IF;
  IF p_kind NOT IN ('IR','ER') THEN RAISE EXCEPTION 'Add an Internal or an External room'; END IF;
  IF coalesce(trim(p_name), '') = '' THEN RAISE EXCEPTION 'Name the room'; END IF;
  IF p_kind = 'ER' AND NOT EXISTS (SELECT 1 FROM room_template WHERE krama_id = r.krama_id AND kind = 'ER') THEN
    RAISE EXCEPTION 'This Krama has no External room';
  END IF;
  IF p_parent IS NOT NULL THEN
    SELECT * INTO par FROM room WHERE room_id = p_parent AND run_id = p_run;
    IF par IS NULL OR par.kind <> 'ER' OR p_kind <> 'ER' THEN RAISE EXCEPTION 'A child room is an External room forked from an External room'; END IF;
    par_with := par.with_entity; par_name := par.name;
  END IF;
  INSERT INTO room (run_id, kind, name, with_entity, parent_room_id, permission)
  VALUES (p_run, p_kind, trim(p_name), CASE WHEN p_kind = 'ER' THEN COALESCE(p_with, r.counterparty) END, p_parent,
          CASE WHEN p_parent IS NOT NULL AND par_with IS NOT NULL THEN 'Requested' ELSE 'Not needed' END)
  RETURNING room_id INTO rid;
  INSERT INTO room_member (room_id, person_id, is_spoc) VALUES (rid, actor, true);
  INSERT INTO room_topic (room_id, topic_id)
  SELECT rid, t.topic_id FROM topic t JOIN stage s USING (stage_id)
   WHERE s.krama_id = r.krama_id AND kind_rank(p_kind) <= path_rank(t.path);
  INSERT INTO registry (room_id, name, description, holds) VALUES (rid, 'Files and events', 'Everything filed or scheduled in this room.', 'Both');
  PERFORM log_run(p_run, actor, 'Room added', p_kind || ' · ' || trim(p_name) || CASE WHEN p_parent IS NOT NULL THEN ' (child of ' || par_name || ')' ELSE '' END);
  RETURN rid;
END $$;

-- The external party of the parent room grants a child room
CREATE FUNCTION grant_room(p_room uuid, actor uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE c record; par record;
BEGIN
  SELECT * INTO c FROM room WHERE room_id = p_room;
  SELECT * INTO par FROM room WHERE room_id = c.parent_room_id;
  IF c.permission <> 'Requested' THEN RAISE EXCEPTION 'This room needs no permission'; END IF;
  IF NOT (in_room(par.room_id, actor) AND is_member_of_entity(actor, par.with_entity)) THEN
    RAISE EXCEPTION 'Only the other party in % can give permission', par.name;
  END IF;
  UPDATE room SET permission = 'Granted' WHERE room_id = p_room;
  PERFORM log_run(c.run_id, actor, 'Room permitted', c.name);
END $$;

CREATE FUNCTION add_room_member(p_room uuid, p_person uuid, actor uuid, p_spoc boolean) RETURNS void LANGUAGE plpgsql AS $$
DECLARE c record; r record;
BEGIN
  SELECT * INTO c FROM room WHERE room_id = p_room;
  SELECT * INTO r FROM run WHERE run_id = c.run_id;
  IF r.requestor_id <> actor THEN RAISE EXCEPTION 'Only the Requestor/Conductor adds people to rooms'; END IF;
  IF user_type_of(p_person) IS DISTINCT FROM 'Individual' THEN RAISE EXCEPTION 'Only a person can join a room'; END IF;
  IF NOT (is_member_of_entity(p_person, r.company_user_id) OR (c.with_entity IS NOT NULL AND is_member_of_entity(p_person, c.with_entity))) THEN
    RAISE EXCEPTION 'The person must belong to this entity or the room''s other party';
  END IF;
  IF c.kind <> 'ER' AND NOT is_member_of_entity(p_person, r.company_user_id) THEN
    RAISE EXCEPTION 'Only this entity''s people sit in Private and Internal rooms';
  END IF;
  INSERT INTO room_member (room_id, person_id, is_spoc) VALUES (p_room, p_person, COALESCE(p_spoc, false))
  ON CONFLICT (room_id, person_id) DO UPDATE SET is_spoc = EXCLUDED.is_spoc;
  PERFORM log_run(c.run_id, actor, 'Joined room', user_name(p_person) || ' → ' || c.name);
END $$;

-- Retain or Delete a topic in a room. A topic must stay in at least one room of each kind on its path;
-- deleting it from the room its questions sit in moves them to another room of that kind that retains it.
CREATE FUNCTION set_room_topic(p_room uuid, p_topic uuid, p_retain boolean, actor uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE c record; r record; other uuid; t record;
BEGIN
  SELECT * INTO c FROM room WHERE room_id = p_room;
  SELECT * INTO r FROM run WHERE run_id = c.run_id;
  SELECT * INTO t FROM topic WHERE topic_id = p_topic;
  IF r.requestor_id <> actor THEN RAISE EXCEPTION 'Only the Requestor/Conductor places topics'; END IF;
  IF kind_rank(c.kind) > path_rank(t.path) THEN RAISE EXCEPTION 'This topic''s path does not reach this room'; END IF;
  IF p_retain THEN
    INSERT INTO room_topic VALUES (p_room, p_topic) ON CONFLICT DO NOTHING;
    PERFORM log_run(c.run_id, actor, 'Topic retained', t.name || ' in ' || c.name);
    RETURN;
  END IF;
  SELECT rt.room_id INTO other FROM room_topic rt JOIN room o ON o.room_id = rt.room_id
   WHERE rt.topic_id = p_topic AND o.run_id = c.run_id AND o.kind = c.kind AND o.room_id <> p_room
   ORDER BY o.created_at LIMIT 1;
  IF other IS NULL THEN RAISE EXCEPTION 'The topic must stay in at least one % room', c.kind; END IF;
  UPDATE question_run x SET room_id = other FROM question q
   WHERE x.question_id = q.question_id AND q.topic_id = p_topic AND x.room_id = p_room;
  DELETE FROM room_topic WHERE room_id = p_room AND topic_id = p_topic;
  PERFORM log_run(c.run_id, actor, 'Topic deleted from room', t.name || ' from ' || c.name);
END $$;

CREATE FUNCTION room_open_to(p_room uuid, actor uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT (is_super(actor) OR in_room(p_room, actor)) AND (SELECT permission <> 'Requested' FROM room WHERE room_id = p_room)
$$;

CREATE FUNCTION add_registry(p_room uuid, actor uuid, p_name text, p_description text, p_holds text) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE g uuid;
BEGIN
  IF NOT room_open_to(p_room, actor) THEN RAISE EXCEPTION 'You are not seated in this room'; END IF;
  IF coalesce(trim(p_name), '') = '' THEN RAISE EXCEPTION 'Name the registry'; END IF;
  INSERT INTO registry (room_id, name, description, holds) VALUES (p_room, trim(p_name), NULLIF(trim(p_description), ''), COALESCE(p_holds, 'Both'))
  RETURNING registry_id INTO g;
  RETURN g;
END $$;

CREATE FUNCTION add_registry_entry(p_registry uuid, actor uuid, p_kind text, p_title text, p_date date, p_stage uuid, p_status text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE g record;
BEGIN
  SELECT * INTO g FROM registry WHERE registry_id = p_registry;
  IF NOT room_open_to(g.room_id, actor) THEN RAISE EXCEPTION 'You are not seated in this room'; END IF;
  IF coalesce(trim(p_title), '') = '' THEN RAISE EXCEPTION 'Give the entry a title'; END IF;
  IF (g.holds = 'Events' AND p_kind = 'File') OR (g.holds = 'Files' AND p_kind = 'Event') THEN
    RAISE EXCEPTION 'This registry holds % only', lower(g.holds);
  END IF;
  IF p_kind = 'Event' AND p_date IS NULL THEN RAISE EXCEPTION 'An event needs a date'; END IF;
  INSERT INTO registry_entry (registry_id, kind, title, on_date, stage_id, status, source_room_id, by_person)
  VALUES (p_registry, p_kind, trim(p_title), p_date, p_stage, COALESCE(p_status, 'Open'), g.room_id, actor);
END $$;

CREATE FUNCTION set_entry_status(p_entry uuid, actor uuid, p_status text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE e record;
BEGIN
  SELECT re.*, g.room_id INTO e FROM registry_entry re JOIN registry g USING (registry_id) WHERE re.entry_id = p_entry;
  IF NOT room_open_to(e.room_id, actor) THEN RAISE EXCEPTION 'You are not seated in this room'; END IF;
  UPDATE registry_entry SET status = p_status WHERE entry_id = p_entry;
END $$;

CREATE FUNCTION post_message(p_room uuid, actor uuid, p_body text, p_mention uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF NOT room_open_to(p_room, actor) OR is_super(actor) AND NOT in_room(p_room, actor) THEN RAISE EXCEPTION 'Only people seated in this room can write here'; END IF;
  IF coalesce(trim(p_body), '') = '' THEN RAISE EXCEPTION 'Write a message'; END IF;
  IF p_mention IS NOT NULL AND NOT EXISTS (SELECT 1 FROM question_run WHERE qr_id = p_mention AND room_id = p_room) THEN
    RAISE EXCEPTION 'You can mention only a question in this room';
  END IF;
  INSERT INTO room_message (room_id, by_person, body, mention_qr) VALUES (p_room, actor, trim(p_body), p_mention);
END $$;


-- ---------- Phase 3: capabilities and the default capabilities of every Krama ----------

CREATE FUNCTION add_capability(p_krama uuid, actor uuid, p_code text, p_stage uuid, p_topic uuid, p_question uuid, p_note text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF NOT can_design(actor, p_krama) THEN RAISE EXCEPTION 'You cannot change this Krama'; END IF;
  IF EXISTS (SELECT 1 FROM capability_use WHERE krama_id = p_krama AND code = p_code
               AND stage_id IS NOT DISTINCT FROM p_stage AND topic_id IS NOT DISTINCT FROM p_topic AND question_id IS NOT DISTINCT FROM p_question) THEN
    RAISE EXCEPTION 'This capability is already applied here';
  END IF;
  INSERT INTO capability_use (krama_id, code, stage_id, topic_id, question_id, note) VALUES (p_krama, p_code, p_stage, p_topic, p_question, NULLIF(trim(p_note), ''));
  PERFORM log_krama(p_krama, actor, 'Capability applied', (SELECT name FROM capability WHERE code = p_code));
END $$;

CREATE FUNCTION remove_capability(p_use uuid, actor uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE u record;
BEGIN
  SELECT * INTO u FROM capability_use WHERE use_id = p_use;
  IF NOT can_design(actor, u.krama_id) THEN RAISE EXCEPTION 'You cannot change this Krama'; END IF;
  DELETE FROM capability_use WHERE use_id = p_use;
  PERFORM log_krama(u.krama_id, actor, 'Capability removed', (SELECT name FROM capability WHERE code = u.code));
END $$;

-- Third-party request: a question in PR or IR sent to an outside party; the reply returns to the same question
CREATE FUNCTION third_party_request(qr uuid, actor uuid, p_party text, p_email text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE c record; k text;
BEGIN
  PERFORM assert_can_act(qr, actor, ARRAY['Doer']);
  SELECT * INTO c FROM qr_ctx(qr);
  SELECT kind INTO k FROM room WHERE room_id = c.room_id;
  IF k = 'ER' THEN RAISE EXCEPTION 'A third-party request is sent from a Private or Internal room, never the External room'; END IF;
  IF c.answer_state NOT IN ('Pending','Contested') THEN RAISE EXCEPTION 'This question is not waiting for an answer'; END IF;
  IF coalesce(trim(p_party), '') = '' OR coalesce(trim(p_email), '') = '' THEN RAISE EXCEPTION 'Name the party and their email'; END IF;
  UPDATE question_run SET third_party = trim(p_party) || ' <' || trim(p_email) || '>' WHERE qr_id = qr;
  INSERT INTO answer_round (qr_id, kind, body, by_person) VALUES (qr, 'Request', 'Sent to ' || trim(p_party) || ' <' || trim(p_email) || '>', actor);
  PERFORM log_run(c.run_id, actor, 'Third-party request', trim(p_party));
END $$;

CREATE FUNCTION third_party_reply(qr uuid, actor uuid, p_reply text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE tp text;
BEGIN
  SELECT third_party INTO tp FROM question_run WHERE qr_id = qr;
  IF tp IS NULL THEN RAISE EXCEPTION 'No third-party request is waiting on this question'; END IF;
  PERFORM submit_answer(qr, actor, p_reply, 'Third party', NULL);
  UPDATE question_run SET third_party = NULL WHERE qr_id = qr;
  UPDATE answer_round SET body = 'Reply from ' || tp || ': ' || p_reply
   WHERE round_id = (SELECT round_id FROM answer_round WHERE qr_id = qr ORDER BY at DESC LIMIT 1);
END $$;

-- Call in and split: an answer in the External room is called into our own PR or IR and split into lines.
-- Only lines marked Under discussion need resolving; the rest count as Agreed.
CREATE FUNCTION call_in_split(p_qr uuid, actor uuid, p_room uuid, p_lines text[], p_discuss int[]) RETURNS void LANGUAGE plpgsql AS $$
DECLARE src record; tr record; i int;
BEGIN
  SELECT x.*, rm.kind AS room_kind, rm.run_id AS rrun INTO src FROM question_run x JOIN room rm ON rm.room_id = x.room_id WHERE x.qr_id = p_qr;
  SELECT * INTO tr FROM room WHERE room_id = p_room;
  IF src.room_kind <> 'ER' THEN RAISE EXCEPTION 'Only something put in the External room can be called in'; END IF;
  IF src.answer IS NULL THEN RAISE EXCEPTION 'There is nothing answered to call in yet'; END IF;
  IF tr.run_id <> src.run_id OR tr.kind = 'ER' THEN RAISE EXCEPTION 'Call it into your own Private or Internal room'; END IF;
  IF NOT (in_room(src.room_id, actor) AND in_room(p_room, actor)) THEN RAISE EXCEPTION 'You must sit in both rooms'; END IF;
  IF EXISTS (SELECT 1 FROM split_line WHERE source_qr = p_qr AND room_id = p_room) THEN RAISE EXCEPTION 'Already called into this room'; END IF;
  IF coalesce(array_length(p_lines, 1), 0) = 0 THEN RAISE EXCEPTION 'Split it into at least one line'; END IF;
  FOR i IN 1 .. array_length(p_lines, 1) LOOP
    IF trim(p_lines[i]) <> '' THEN
      INSERT INTO split_line (source_qr, room_id, seq, text, state, by_person)
      VALUES (p_qr, p_room, i, trim(p_lines[i]), CASE WHEN i = ANY (coalesce(p_discuss, '{}')) THEN 'Under discussion' ELSE 'Agreed' END, actor);
    END IF;
  END LOOP;
  PERFORM log_run(src.run_id, actor, 'Called in and split', tr.name);
END $$;

CREATE FUNCTION settle_split_line(p_line uuid, actor uuid, p_note text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE l record;
BEGIN
  SELECT * INTO l FROM split_line WHERE line_id = p_line;
  IF NOT in_room(l.room_id, actor) THEN RAISE EXCEPTION 'You are not seated in this room'; END IF;
  UPDATE split_line SET state = 'Agreed', note = NULLIF(trim(p_note), '') WHERE line_id = p_line;
END $$;

-- Estimation vs Execution. Opportunity and Deal show Estimation only; Order management and Process show both.
CREATE FUNCTION add_estimate_line(p_run uuid, actor uuid, p_item text, p_source text, p_vendor uuid, p_vendor_name text,
                                  p_cost numeric, p_price numeric, p_days numeric) RETURNS void LANGUAGE plpgsql AS $$
DECLARE r record;
BEGIN
  SELECT * INTO r FROM run WHERE run_id = p_run;
  IF r.requestor_id <> actor THEN RAISE EXCEPTION 'Only the Requestor/Conductor builds the estimate'; END IF;
  IF r.locked_at IS NOT NULL THEN RAISE EXCEPTION 'This run is conserved; amend it first'; END IF;
  IF coalesce(trim(p_item), '') = '' THEN RAISE EXCEPTION 'Name the line item'; END IF;
  IF p_source = 'Borrowed' AND p_vendor IS NULL AND coalesce(trim(p_vendor_name), '') = '' THEN RAISE EXCEPTION 'A Borrowed line names its vendor'; END IF;
  INSERT INTO estimate_line (run_id, item, source, vendor_id, vendor_name, est_cost, est_price, est_days)
  VALUES (p_run, trim(p_item), p_source, CASE WHEN p_source = 'Borrowed' THEN p_vendor END,
          CASE WHEN p_source = 'Borrowed' AND p_vendor IS NULL THEN NULLIF(trim(p_vendor_name), '') END, p_cost, p_price, p_days);
  PERFORM log_run(p_run, actor, 'Estimate line', trim(p_item));
END $$;

CREATE FUNCTION set_actuals(p_line uuid, actor uuid, p_cost numeric, p_price numeric, p_days numeric) RETURNS void LANGUAGE plpgsql AS $$
DECLARE l record; r record;
BEGIN
  SELECT * INTO l FROM estimate_line WHERE line_id = p_line;
  SELECT * INTO r FROM run WHERE run_id = l.run_id;
  IF r.requestor_id <> actor THEN RAISE EXCEPTION 'Only the Requestor/Conductor records execution'; END IF;
  IF (SELECT tag_domain FROM krama WHERE krama_id = r.krama_id) IN ('Opportunity','Deal') THEN
    RAISE EXCEPTION 'Opportunity and Deal show Estimation only; execution comes in Order management';
  END IF;
  UPDATE estimate_line SET act_cost = p_cost, act_price = p_price, act_days = p_days WHERE line_id = p_line;
END $$;

-- Vendor invite chain status for a Borrowed line
CREATE FUNCTION line_source_status(l estimate_line) RETURNS text LANGUAGE sql STABLE AS $$
  SELECT CASE
    WHEN l.source = 'Owned' THEN 'Owned'
    WHEN l.vendor_id IS NULL THEN 'Pending · vendor invited to create its entity'
    WHEN EXISTS (SELECT 1 FROM catalogue_item ci WHERE ci.company_user_id = l.vendor_id) THEN 'Borrowed · mapped to the vendor''s catalogue'
    ELSE 'Pending · vendor invited to add a catalogue item' END
$$;
