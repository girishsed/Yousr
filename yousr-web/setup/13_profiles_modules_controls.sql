-- =====================================================================================
-- 1. Dept/BU profile (the framework lists Department and Business Unit as Entity Profile examples)
-- 2. Module pick-list for Kramas (a defined list instead of free text)
-- 3. Domain controls applied: a stage's domain controls become checks a task must confirm
-- =====================================================================================

-- ---------- 1. Dept/BU profile ----------
ALTER TABLE dept_bu ADD COLUMN objectives text,
                    ADD COLUMN capabilities text[] NOT NULL DEFAULT '{}',
                    ADD COLUMN areas_of_operation text[] NOT NULL DEFAULT '{}',
                    ADD COLUMN business_interests text[] NOT NULL DEFAULT '{}';

CREATE FUNCTION api_dept_profile(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
DECLARE d record;
BEGIN
  SELECT * INTO d FROM dept_bu WHERE dept_bu_id = (b->>'dept_bu_id')::uuid;
  IF d IS NULL THEN RAISE EXCEPTION 'Dept/BU not found'; END IF;
  IF b ? 'save' THEN
    PERFORM need_admin(actor, d.company_user_id);
    UPDATE dept_bu SET objectives = j(b->'save', 'objectives'), capabilities = lines(b->'save'->>'capabilities'),
           areas_of_operation = lines(b->'save'->>'areas_of_operation'), business_interests = lines(b->'save'->>'business_interests')
     WHERE dept_bu_id = d.dept_bu_id;
  ELSE PERFORM need_member(actor, d.company_user_id);
  END IF;
  RETURN (SELECT json_build_object('name', x.name, 'objectives', x.objectives, 'capabilities', x.capabilities, 'areas_of_operation', x.areas_of_operation,
            'business_interests', x.business_interests,
            'head', (SELECT wp.name FROM work_persona wp JOIN grade g ON g.grade_id = wp.grade_id WHERE wp.dept_bu_id = x.dept_bu_id ORDER BY g.rank LIMIT 1),
            'people', (SELECT count(*) FROM person_entity_link l WHERE l.dept_bu_id = x.dept_bu_id))
            FROM dept_bu x WHERE x.dept_bu_id = d.dept_bu_id);
END $$;

UPDATE dept_bu SET objectives = 'Pay vendors and employees correctly and on time.', capabilities = '{Payables,Reimbursements,Month-end close}'
 WHERE company_user_id = '11111111-0000-0000-0000-000000000012' AND name = 'Finance';

-- ---------- 2. Module pick-list ----------
CREATE TABLE krama_module (
  name text PRIMARY KEY,
  note text
);
INSERT INTO krama_module (name, note) VALUES
 ('Opportunity', 'Sell side; platform built only; estimation only'),
 ('Deal', 'Buy side; platform built only; estimation only'),
 ('Order management', 'Platform built only'),
 ('Network', NULL),
 ('Process', NULL);
-- Every Krama's Module must come from the list (empty means none)
INSERT INTO krama_module (name) SELECT DISTINCT tag_domain FROM krama WHERE COALESCE(tag_domain, '') <> '' ON CONFLICT DO NOTHING;
UPDATE krama SET tag_domain = NULL WHERE tag_domain = '';
ALTER TABLE krama ADD CONSTRAINT krama_module_fk FOREIGN KEY (tag_domain) REFERENCES krama_module(name);

CREATE FUNCTION api_krama_modules(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
BEGIN
  IF j(b, 'add') IS NOT NULL THEN
    IF NOT is_super(actor) THEN RAISE EXCEPTION 'Only the platform super-user adds modules'; END IF;
    INSERT INTO krama_module (name, note) VALUES (j(b, 'add'), j(b, 'note')) ON CONFLICT DO NOTHING;
  END IF;
  RETURN (SELECT COALESCE(json_agg(json_build_object('name', name, 'note', note) ORDER BY name), '[]') FROM krama_module);
END $$;

-- ---------- 3. Domain controls applied ----------
-- Each control of a stage's domain profile is a check the task confirms; confirmations are recorded here
CREATE TABLE control_check (
  run_id   uuid NOT NULL REFERENCES run(run_id) ON DELETE CASCADE,
  stage_id uuid NOT NULL REFERENCES stage(stage_id),
  control  text NOT NULL,
  by_person uuid NOT NULL REFERENCES users(user_id),
  at       timestamptz NOT NULL DEFAULT clock_timestamp(),
  note     text,
  PRIMARY KEY (run_id, stage_id, control)
);

-- The controls a stage must confirm: its domain profile's expected controls
CREATE FUNCTION stage_controls(p_stage uuid) RETURNS text[] LANGUAGE sql STABLE AS $$
  SELECT COALESCE((SELECT dp.controls FROM stage s JOIN domain_profile dp ON dp.domain_id = s.domain_id WHERE s.stage_id = p_stage), '{}')
$$;
CREATE FUNCTION controls_pending(p_run uuid, p_stage uuid) RETURNS integer LANGUAGE sql STABLE AS $$
  SELECT count(*)::int FROM unnest(stage_controls(p_stage)) c
   WHERE NOT EXISTS (SELECT 1 FROM control_check k WHERE k.run_id = p_run AND k.stage_id = p_stage AND k.control = c)
$$;

-- A task closes only when every question is closed and every stage control is confirmed
CREATE OR REPLACE FUNCTION check_run(p_run uuid, actor uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE res text;
BEGIN
  IF EXISTS (SELECT 1 FROM question_run WHERE run_id = p_run AND status = 'Open') THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM stage s JOIN run r ON r.krama_id = s.krama_id WHERE r.run_id = p_run AND controls_pending(p_run, s.stage_id) > 0) THEN RETURN; END IF;
  res := CASE WHEN EXISTS (SELECT 1 FROM question_run WHERE run_id = p_run AND closed_as = 'Dropped')
              THEN 'Unfulfilled' ELSE 'Fulfilled' END;
  UPDATE run SET status = 'Closed', result = res, locked_at = clock_timestamp() WHERE run_id = p_run;
  PERFORM log_run(p_run, NULL, 'Run ' || res, 'Locked and conserved under ' || (SELECT fy FROM run WHERE run_id = p_run));
END $$;

-- A gated stage also waits for its controls before the next stage opens
CREATE OR REPLACE FUNCTION qr_ctx(qr uuid) RETURNS TABLE (run_id uuid, stage_id uuid, room_id uuid, status text, answer_state text, locked boolean)
LANGUAGE sql STABLE AS $$
  SELECT x.run_id, t.stage_id, x.room_id, x.status, x.answer_state,
         EXISTS (SELECT 1 FROM question_link l JOIN question_run p ON p.run_id = x.run_id AND p.question_id = l.predecessor_id
                  WHERE l.question_id = x.question_id AND NOT (p.status = 'Closed' AND COALESCE(p.closed_as, 'Success') = 'Success'))
         OR EXISTS (SELECT 1 FROM capability_use cu JOIN stage gs ON gs.stage_id = cu.stage_id JOIN stage me ON me.stage_id = t.stage_id
                     WHERE cu.code = 'stage_gate' AND gs.krama_id = me.krama_id AND gs.seq < me.seq
                       AND (EXISTS (SELECT 1 FROM question_run y JOIN question qy ON qy.question_id = y.question_id JOIN topic ty ON ty.topic_id = qy.topic_id
                                    WHERE y.run_id = x.run_id AND ty.stage_id = gs.stage_id
                                      AND NOT (y.status = 'Closed' AND COALESCE(y.closed_as, 'Success') = 'Success'))
                            OR controls_pending(x.run_id, gs.stage_id) > 0))
    FROM question_run x JOIN question q USING (question_id) JOIN topic t USING (topic_id)
   WHERE x.qr_id = qr
$$;

-- Confirm (or withdraw) a control: the Reviewer or Approver of that stage, or the Requestor/Conductor
CREATE FUNCTION api_confirm_control(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
DECLARE r run; st uuid := (b->>'stage_id')::uuid; c text := j(b, 'control');
BEGIN
  SELECT * INTO r FROM run WHERE run_id = (b->>'run_id')::uuid;
  IF r IS NULL THEN RAISE EXCEPTION 'Task not found'; END IF;
  IF r.locked_at IS NOT NULL THEN RAISE EXCEPTION 'This task is conserved; amend it first'; END IF;
  IF NOT (c = ANY (stage_controls(st))) THEN RAISE EXCEPTION 'That is not a control of this stage'; END IF;
  IF NOT (r.requestor_id = actor OR has_seat(r.run_id, st, actor, ARRAY['Reviewer','Approver'])) THEN
    RAISE EXCEPTION 'Only the Reviewer or Approver of this stage, or the Requestor/Conductor, confirms its controls';
  END IF;
  IF COALESCE((b->>'withdraw')::boolean, false) THEN
    DELETE FROM control_check WHERE run_id = r.run_id AND stage_id = st AND control = c;
    PERFORM log_run(r.run_id, actor, 'Control withdrawn', c);
  ELSE
    INSERT INTO control_check (run_id, stage_id, control, by_person, note) VALUES (r.run_id, st, c, actor, j(b, 'note'))
    ON CONFLICT (run_id, stage_id, control) DO NOTHING;
    PERFORM log_run(r.run_id, actor, 'Control confirmed', c);
    PERFORM check_run(r.run_id, actor);
  END IF;
  RETURN json_build_object('ok', true);
END $$;

-- The task context now lists each stage's controls with who confirmed them
CREATE FUNCTION api_task_controls(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql STABLE AS $$
DECLARE r run;
BEGIN
  SELECT * INTO r FROM run WHERE run_id = (b->>'run_id')::uuid;
  IF r IS NULL OR r.run_id NOT IN (SELECT visible_runs(actor)) THEN RAISE EXCEPTION 'Task not found'; END IF;
  RETURN (SELECT COALESCE(json_agg(json_build_object('stage_id', s.stage_id, 'stage', s.name,
            'can_confirm', r.locked_at IS NULL AND (r.requestor_id = actor OR has_seat(r.run_id, s.stage_id, actor, ARRAY['Reviewer','Approver'])),
            'controls', (SELECT json_agg(json_build_object('control', c,
                           'by', (SELECT user_name(k.by_person) FROM control_check k WHERE k.run_id = r.run_id AND k.stage_id = s.stage_id AND k.control = c),
                           'at', (SELECT to_char(k.at AT TIME ZONE 'Asia/Kolkata', 'DD Mon HH24:MI') FROM control_check k WHERE k.run_id = r.run_id AND k.stage_id = s.stage_id AND k.control = c)))
                         FROM unnest(stage_controls(s.stage_id)) c)) ORDER BY s.seq), '[]')
            FROM stage s WHERE s.krama_id = r.krama_id AND cardinality(stage_controls(s.stage_id)) > 0);
END $$;
