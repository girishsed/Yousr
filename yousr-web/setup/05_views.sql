-- Read views for the screens (FRD v3.0)

-- Stage and topic status is arithmetic on their questions
CREATE FUNCTION status_of(p_run uuid, p_stage uuid, p_topic uuid) RETURNS text LANGUAGE sql STABLE AS $$
  WITH q AS (
    SELECT x.* FROM question_run x JOIN question qq USING (question_id) JOIN topic t USING (topic_id)
     WHERE x.run_id = p_run AND (t.stage_id = p_stage OR t.topic_id = p_topic))
  SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM q) THEN 'Open'
              WHEN EXISTS (SELECT 1 FROM q WHERE status = 'Open') THEN 'Open'
              WHEN EXISTS (SELECT 1 FROM q WHERE closed_as = 'Dropped') THEN 'Closed · Dropped'
              ELSE 'Closed · Success' END
$$;

CREATE FUNCTION run_label(r run) RETURNS text LANGUAGE sql IMMUTABLE AS
$$ SELECT r.instance_code || CASE WHEN r.amendment_no > 0 THEN ' · A' || r.amendment_no ELSE '' END $$;

CREATE FUNCTION runs_json(actor uuid) RETURNS json LANGUAGE sql STABLE AS $$
  SELECT COALESCE(json_agg(json_build_object(
    'run_id', r.run_id, 'label', run_label(r), 'item', ci.name, 'fy', r.fy, 'status', r.status, 'result', r.result,
    'locked', r.locked_at IS NOT NULL, 'requestor_name', user_name(r.requestor_id),
    'entity_name', user_name(r.company_user_id), 'counterparty_name', user_name(r.counterparty))
    ORDER BY r.started_on DESC, r.instance_code DESC), '[]')
  FROM run r JOIN catalogue_item ci USING (item_id)
  WHERE r.run_id IN (SELECT visible_runs(actor))
$$;

CREATE FUNCTION rounds_json(qr uuid) RETURNS json LANGUAGE sql STABLE AS $$
  SELECT COALESCE(json_agg(json_build_object('kind', kind, 'body', body, 'data', data, 'reason', reason, 'explanation', explanation,
           'by_name', user_name(by_person), 'at', to_char(at AT TIME ZONE 'Asia/Kolkata', 'DD Mon HH24:MI')) ORDER BY at), '[]')
    FROM answer_round WHERE qr_id = qr
$$;

CREATE FUNCTION expertise_json(p_stage uuid, p_topic uuid, p_question uuid) RETURNS json LANGUAGE sql STABLE AS $$
  SELECT COALESCE(json_agg(json_build_object('requirement_id', r.requirement_id, 'expertise_id', r.expertise_id,
           'name', e.name, 'mapped_as', r.mapped_as) ORDER BY r.mapped_as DESC, e.name), '[]')
    FROM expertise_required r JOIN expertise e USING (expertise_id)
   WHERE (p_stage IS NOT NULL AND r.stage_id = p_stage) OR (p_topic IS NOT NULL AND r.topic_id = p_topic)
      OR (p_question IS NOT NULL AND r.question_id = p_question)
$$;

-- One run as the person may see it: rooms they sit in, and questions in those rooms (agreed ones travel along the path)
-- Capability names applied at a stage, topic or question
CREATE FUNCTION caps_at(p_stage uuid, p_topic uuid, p_question uuid) RETURNS json LANGUAGE sql STABLE AS $$
  SELECT COALESCE(json_agg(json_build_object('use_id', cu.use_id, 'code', cu.code, 'name', c.name, 'note', cu.note) ORDER BY c.seq), '[]')
    FROM capability_use cu JOIN capability c USING (code)
   WHERE (p_stage IS NOT NULL AND cu.stage_id = p_stage) OR (p_topic IS NOT NULL AND cu.topic_id = p_topic)
      OR (p_question IS NOT NULL AND cu.question_id = p_question)
$$;

-- A person as a picker option inside one instance: their entity and Dept/BU there, and their expertise
CREATE FUNCTION person_option(p uuid, e uuid) RETURNS json LANGUAGE sql STABLE AS $$
  SELECT json_build_object('user_id', p, 'name', user_name(p), 'entity_id', e, 'entity', user_name(e),
    'dept', (SELECT d.name FROM person_entity_link l JOIN dept_bu d ON d.dept_bu_id = l.dept_bu_id WHERE l.person_id = p AND l.company_user_id = e),
    'expertise_ids', (SELECT to_json(expertise_ids) FROM users WHERE user_id = p))
$$;

CREATE FUNCTION run_tree(p_run uuid, actor uuid) RETURNS json LANGUAGE sql STABLE AS $$
  SELECT CASE WHEN p_run NOT IN (SELECT visible_runs(actor)) THEN NULL ELSE (
  SELECT json_build_object(
    'run_id', r.run_id, 'label', run_label(r), 'item', ci.name, 'krama', k.name, 'version', k.version,
    'fy', r.fy, 'status', r.status, 'result', r.result, 'locked', r.locked_at IS NOT NULL,
    'requestor_id', r.requestor_id, 'requestor_name', user_name(r.requestor_id), 'relationship', r.relationship,
    'entity_name', user_name(r.company_user_id), 'counterparty', r.counterparty, 'counterparty_name', user_name(r.counterparty),
    'counterparty_persona', (SELECT pt.display_name FROM company c JOIN persona_type pt USING (persona_type_id) WHERE c.user_id = r.counterparty),
    'is_requestor', r.requestor_id = actor, 'is_super', is_super(actor),
    'rooms', (SELECT json_agg(json_build_object('room_id', rm.room_id, 'kind', rm.kind, 'name', rm.name,
                'with_name', user_name(rm.with_entity), 'parent_room_id', rm.parent_room_id,
                'parent_name', (SELECT name FROM room p WHERE p.room_id = rm.parent_room_id), 'permission', rm.permission,
                'can_grant', rm.permission = 'Requested' AND EXISTS (SELECT 1 FROM room p WHERE p.room_id = rm.parent_room_id
                               AND in_room(p.room_id, actor) AND is_member_of_entity(actor, p.with_entity)),
                'topics', (SELECT COALESCE(json_agg(rt.topic_id), '[]') FROM room_topic rt WHERE rt.room_id = rm.room_id),
                'member', rm.room_id IN (SELECT my_rooms(actor)),
                'members', (SELECT COALESCE(json_agg(json_build_object('name', user_name(m.person_id), 'spoc', m.is_spoc)
                              ORDER BY user_name(m.person_id)), '[]') FROM room_member m WHERE m.room_id = rm.room_id),
                -- Who can still be added: this entity's people; in an External room also the room's other party
                'candidates', (SELECT COALESCE(json_agg(person_option(l.person_id, l.company_user_id)
                                 ORDER BY l.company_user_id <> r.company_user_id, user_name(l.person_id)), '[]')
                                 FROM person_entity_link l
                                WHERE (r.requestor_id = actor OR is_super(actor))
                                  AND (l.company_user_id = r.company_user_id
                                       OR (rm.kind = 'ER' AND l.company_user_id = rm.with_entity AND NOT is_member_of_entity(l.person_id, r.company_user_id)))
                                  AND NOT EXISTS (SELECT 1 FROM room_member m WHERE m.room_id = rm.room_id AND m.person_id = l.person_id)))
              ORDER BY kind_rank(rm.kind), rm.created_at) FROM room rm WHERE rm.run_id = r.run_id),
    'seats', (SELECT COALESCE(json_agg(json_build_object('seat_id', s.seat_id, 'stage_id', s.stage_id, 'seat', s.seat,
                'person_id', s.person_id, 'person_name', user_name(s.person_id)) ORDER BY s.seat, user_name(s.person_id)), '[]')
              FROM seat s WHERE s.run_id = r.run_id),
    'reports', (SELECT COALESCE(json_agg(json_build_object('name', rp.name, 'question_text', rp.question_text)), '[]')
                FROM report rp WHERE rp.krama_id = r.krama_id),
    'split', (SELECT COALESCE(json_agg(json_build_object('source_qr', g.source_qr, 'room_id', g.room_id,
                 'question', (SELECT q.text FROM question_run x JOIN question q USING (question_id) WHERE x.qr_id = g.source_qr),
                 'lines', (SELECT json_agg(json_build_object('line_id', l.line_id, 'text', l.text, 'state', l.state, 'note', l.note) ORDER BY l.seq)
                             FROM split_line l WHERE l.source_qr = g.source_qr AND l.room_id = g.room_id))), '[]')
              FROM (SELECT DISTINCT source_qr, room_id FROM split_line sl JOIN room rm USING (room_id)
                     WHERE rm.run_id = r.run_id AND (is_super(actor) OR in_room(sl.room_id, actor))) g),
    'outputs', (SELECT COALESCE(json_agg(json_build_object('topic', t.name, 'stage', s.name,
                  'total', (SELECT count(*) FROM question_run x JOIN question q USING (question_id) WHERE x.run_id = r.run_id AND q.topic_id = t.topic_id
                              AND x.answer_state <> 'Cancelled'),
                  'agreed', (SELECT count(*) FROM question_run x JOIN question q USING (question_id) WHERE x.run_id = r.run_id AND q.topic_id = t.topic_id
                              AND x.answer_state = 'Agreed'),
                  'lines', (SELECT COALESCE(json_agg(json_build_object('question', q.text, 'answer', x.answer, 'agreed', x.answer_state = 'Agreed') ORDER BY q.seq), '[]')
                              FROM question_run x JOIN question q USING (question_id) WHERE x.run_id = r.run_id AND q.topic_id = t.topic_id
                               AND x.answer_state <> 'Cancelled' AND can_see_qr(x.qr_id, actor)),
                  'files', (SELECT COALESCE(json_agg(COALESCE(x.answer_data->>'file', x.answer_data->'attachment'->>'file')), '[]')
                              FROM question_run x JOIN question q USING (question_id) WHERE x.run_id = r.run_id AND q.topic_id = t.topic_id
                               AND COALESCE(x.answer_data->>'file', x.answer_data->'attachment'->>'file') IS NOT NULL AND can_see_qr(x.qr_id, actor)))
                  ORDER BY s.seq, t.seq), '[]')
                FROM topic t JOIN stage s USING (stage_id) WHERE s.krama_id = r.krama_id AND t.is_output),
    'estimation_only', k.tag_domain IN ('Opportunity','Deal'),
    'estimates', (SELECT COALESCE(json_agg(json_build_object('line_id', l.line_id, 'item', l.item, 'source', l.source,
                    'vendor', COALESCE(user_name(l.vendor_id), l.vendor_name), 'status', line_source_status(l),
                    'est_cost', l.est_cost, 'est_price', l.est_price, 'est_days', l.est_days,
                    'act_cost', l.act_cost, 'act_price', l.act_price, 'act_days', l.act_days) ORDER BY l.at), '[]')
                  FROM estimate_line l WHERE l.run_id = r.run_id AND (is_super(actor) OR is_member_of_entity(actor, r.company_user_id))),
    'overview', (SELECT json_agg(json_build_object('kind', rm.kind, 'name', rm.name,
                   'open', (SELECT count(*) FROM question_run x WHERE x.room_id = rm.room_id AND x.status = 'Open'),
                   'success', (SELECT count(*) FROM question_run x WHERE x.room_id = rm.room_id AND x.closed_as = 'Success'),
                   'dropped', (SELECT count(*) FROM question_run x WHERE x.room_id = rm.room_id AND x.closed_as = 'Dropped'),
                   'cancelled', (SELECT count(*) FROM question_run x WHERE x.room_id = rm.room_id AND x.answer_state = 'Cancelled'))
                   ORDER BY kind_rank(rm.kind))
                 FROM room rm WHERE rm.run_id = r.run_id AND (is_super(actor) OR rm.room_id IN (SELECT my_rooms(actor)))),
    'stages', (SELECT COALESCE(json_agg(json_build_object(
        'stage_id', s.stage_id, 'name', s.name, 'path', s.path, 'status', status_of(r.run_id, s.stage_id, NULL),
        'expertise', expertise_json(s.stage_id, NULL, NULL), 'capabilities', caps_at(s.stage_id, NULL, NULL),
        -- Who can be seated: this entity's people; the counterparty's only on a stage that reaches the external room
        'candidates', (SELECT COALESCE(json_agg(person_option(l.person_id, l.company_user_id)
                         ORDER BY l.company_user_id <> r.company_user_id, user_name(l.person_id)), '[]')
                         FROM person_entity_link l
                        WHERE (r.requestor_id = actor OR is_super(actor))
                          AND (l.company_user_id = r.company_user_id
                               OR (l.company_user_id = r.counterparty AND path_rank(s.path) >= 3
                                   AND NOT is_member_of_entity(l.person_id, r.company_user_id)))),
        'my_seats', (SELECT COALESCE(json_agg(seat), '[]') FROM seat WHERE run_id = r.run_id AND stage_id = s.stage_id AND person_id = actor),
        'topics', (SELECT COALESCE(json_agg(json_build_object(
            'topic_id', t.topic_id, 'name', t.name, 'path', t.path, 'status', status_of(r.run_id, NULL, t.topic_id),
            'is_output', t.is_output, 'capabilities', caps_at(NULL, t.topic_id, NULL),
            'questions', (SELECT COALESCE(json_agg(json_build_object(
                'qr_id', x.qr_id, 'room_id', x.room_id, 'text', q.text, 'flow_option', q.flow_option, 'rules', q.rules, 'ask_in', q.ask_in,
                'setup_options', q.setup_options, 'setup_choices', q.setup_choices, 'setup_multi', q.setup_multi,
                'setup_columns', q.setup_columns, 'setup_limit', q.setup_limit, 'also_needs', q.also_needs, 'answer_data', x.answer_data,
                'removal_asked', (SELECT kind = 'Contest' AND reason = 'Remove' FROM answer_round ar WHERE ar.qr_id = x.qr_id ORDER BY at DESC LIMIT 1),
                'status', x.status, 'closed_as', x.closed_as, 'state', x.answer_state, 'answer', x.answer, 'source', x.source,
                'due_date', x.due_date, 'reopen_count', x.reopen_count, 'quadrant', x.quadrant,
                'capabilities', caps_at(NULL, NULL, q.question_id), 'third_party', x.third_party,
                'room_kind', (SELECT kind FROM room WHERE room_id = x.room_id),
                'with_me', is_with(x.qr_id, actor),
                'locked', (SELECT locked FROM qr_ctx(x.qr_id)),
                'waits_for', (SELECT COALESCE(json_agg(pq.text), '[]') FROM question_link l JOIN question pq ON pq.question_id = l.predecessor_id
                               JOIN question_run px ON px.run_id = x.run_id AND px.question_id = l.predecessor_id
                              WHERE l.question_id = q.question_id AND NOT (px.status = 'Closed' AND COALESCE(px.closed_as, 'Success') = 'Success')),
                'in_my_room', x.room_id IN (SELECT my_rooms(actor)),
                'last_submitter', last_submitter(x.qr_id),
                'reviewed', EXISTS (SELECT 1 FROM answer_round ar WHERE ar.qr_id = x.qr_id AND ar.kind = 'Review'
                                      AND ar.at > COALESCE((SELECT max(at) FROM answer_round WHERE qr_id = x.qr_id AND kind = 'Submit'), 'epoch')),
                'has_reviewer', EXISTS (SELECT 1 FROM seat WHERE run_id = r.run_id AND stage_id = s.stage_id AND seat = 'Reviewer'),
                'rounds', rounds_json(x.qr_id)) ORDER BY q.seq), '[]')
              FROM question_run x JOIN question q USING (question_id)
             WHERE x.run_id = r.run_id AND q.topic_id = t.topic_id AND can_see_qr(x.qr_id, actor)))
          ORDER BY t.seq), '[]') FROM topic t WHERE t.stage_id = s.stage_id
            AND EXISTS (SELECT 1 FROM question_run x JOIN question q USING (question_id)
                         WHERE x.run_id = r.run_id AND q.topic_id = t.topic_id AND can_see_qr(x.qr_id, actor))))
      ORDER BY s.seq), '[]') FROM stage s WHERE s.krama_id = r.krama_id
        AND EXISTS (SELECT 1 FROM question_run x JOIN question q USING (question_id) JOIN topic t USING (topic_id)
                     WHERE x.run_id = r.run_id AND t.stage_id = s.stage_id AND can_see_qr(x.qr_id, actor))))
  FROM run r JOIN catalogue_item ci USING (item_id) JOIN krama k ON k.krama_id = r.krama_id
  WHERE r.run_id = p_run) END
$$;

-- Home: questions waiting on the person, and conserved runs
CREATE FUNCTION home_json(actor uuid) RETURNS json LANGUAGE sql STABLE AS $$
  WITH w AS (
    SELECT x.*, r.instance_code, r.amendment_no, ci.name AS item, q.text, t.stage_id
      FROM question_run x JOIN run r USING (run_id) JOIN catalogue_item ci USING (item_id)
      JOIN question q USING (question_id) JOIN topic t USING (topic_id)
     WHERE x.status = 'Open' AND r.locked_at IS NULL AND x.room_id IN (SELECT my_rooms(actor))
       AND NOT (SELECT locked FROM qr_ctx(x.qr_id)))
  SELECT json_build_object(
    'to_answer', (SELECT COALESCE(json_agg(json_build_object('run_id', run_id, 'qr_id', qr_id, 'question', text, 'item', item,
                    'label', instance_code || CASE WHEN amendment_no > 0 THEN ' · A' || amendment_no ELSE '' END,
                    'state', answer_state, 'quadrant', quadrant, 'due_date', due_date) ORDER BY due_date), '[]')
                  FROM w WHERE answer_state IN ('Pending','Contested') AND is_with(qr_id, actor)),
    'to_decide', (SELECT COALESCE(json_agg(json_build_object('run_id', run_id, 'qr_id', qr_id, 'question', text, 'item', item,
                    'label', instance_code || CASE WHEN amendment_no > 0 THEN ' · A' || amendment_no ELSE '' END,
                    'state', answer_state, 'quadrant', quadrant, 'due_date', due_date, 'from', user_name(last_submitter(qr_id))) ORDER BY due_date), '[]')
                  FROM w WHERE answer_state = 'Submitted' AND is_with(qr_id, actor)),
    'conserved', (SELECT COALESCE(json_agg(json_build_object('run_id', r.run_id, 'label', run_label(r), 'item', ci.name,
                    'result', r.result, 'fy', r.fy) ORDER BY r.locked_at DESC), '[]')
                  FROM run r JOIN catalogue_item ci USING (item_id)
                 WHERE r.locked_at IS NOT NULL AND r.run_id IN (SELECT visible_runs(actor))),
    'standalone', (SELECT COALESCE(json_agg(json_build_object('task_id', task_id, 'title', title, 'notes', notes,
                    'due_date', due_date, 'quadrant', quadrant, 'status', status, 'entity_name', user_name(company_user_id),
                    'entity_id', company_user_id, 'fy', fy, 'done_on', to_char(done_at AT TIME ZONE 'Asia/Kolkata', 'DD Mon YYYY'))
                    ORDER BY status, CASE quadrant WHEN 'Do now' THEN 1 WHEN 'Do later' THEN 2 WHEN 'Delegate' THEN 3 ELSE 4 END, due_date), '[]')
                   FROM standalone_task WHERE owner_id = actor),
    'entities', (SELECT COALESCE(json_agg(json_build_object('entity_id', company_user_id, 'name', user_name(company_user_id))), '[]')
                 FROM person_entity_link WHERE person_id = actor))
$$;

-- The entity a person sees a run under: their own side (the running entity, or the counterparty)
CREATE FUNCTION run_entity_for(p_run uuid, p uuid) RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT CASE WHEN p_run IS NULL THEN NULL
              WHEN is_member_of_entity(p, r.company_user_id) THEN r.company_user_id
              WHEN r.counterparty IS NOT NULL AND is_member_of_entity(p, r.counterparty) THEN r.counterparty
              ELSE r.company_user_id END
    FROM run r WHERE r.run_id = p_run
$$;

-- The calendar is personal: questions you are seated on, your own actions, and your own Standalone tasks
CREATE FUNCTION calendar_json(actor uuid, p_from date, p_to date) RETURNS json LANGUAGE sql STABLE AS $$
  SELECT COALESCE(json_agg(z ORDER BY z->>'date', z->>'kind', z->>'at'), '[]') FROM (
    -- due: open questions where it is your turn (Doer, then Reviewer, then Approver / SPOC)
    SELECT json_build_object('date', x.due_date, 'kind', 'due', 'at', NULL, 'title', 'Due: ' || q.text,
             'process', ci.name, 'who', NULL, 'run_id', x.run_id, 'proc_instance_id', x.qr_id,
             'entity_id', run_entity_for(r.run_id, actor), 'entity_name', user_name(run_entity_for(r.run_id, actor))) AS z
      FROM question_run x JOIN question q USING (question_id)
      JOIN run r USING (run_id) JOIN catalogue_item ci USING (item_id)
     WHERE x.status = 'Open' AND x.due_date BETWEEN p_from AND p_to AND is_with(x.qr_id, actor)
    UNION ALL
    -- due: your open Standalone tasks
    SELECT json_build_object('date', st.due_date, 'kind', 'due', 'at', NULL, 'title', 'Due: ' || st.title,
             'process', 'Standalone · ' || st.quadrant, 'who', NULL, 'run_id', NULL, 'proc_instance_id', NULL)
      FROM standalone_task st
     WHERE st.owner_id = actor AND st.status = 'Open' AND st.due_date BETWEEN p_from AND p_to
    UNION ALL
    -- what happened on questions you are seated on
    SELECT json_build_object('date', (ar.at AT TIME ZONE 'Asia/Kolkata')::date, 'kind', 'activity',
             'at', to_char(ar.at AT TIME ZONE 'Asia/Kolkata', 'HH24:MI'), 'title', ar.kind || ': ' || q.text,
             'process', ci.name, 'who', user_name(ar.by_person), 'run_id', x.run_id, 'proc_instance_id', x.qr_id,
             'entity_id', run_entity_for(r.run_id, actor), 'entity_name', user_name(run_entity_for(r.run_id, actor)))
      FROM answer_round ar JOIN question_run x USING (qr_id) JOIN question q USING (question_id) JOIN topic t USING (topic_id)
      JOIN run r USING (run_id) JOIN catalogue_item ci USING (item_id)
     WHERE (ar.at AT TIME ZONE 'Asia/Kolkata')::date BETWEEN p_from AND p_to
       AND has_seat(x.run_id, t.stage_id, actor, ARRAY['Doer','Reviewer','Approver','SPOC'])
    UNION ALL
    -- your own actions that are not answers (activations, seating, amendments, Standalone)
    SELECT json_build_object('date', (a.at AT TIME ZONE 'Asia/Kolkata')::date, 'kind', 'activity',
             'at', to_char(a.at AT TIME ZONE 'Asia/Kolkata', 'HH24:MI'), 'title', a.action || COALESCE(': ' || a.detail, ''),
             'process', COALESCE((SELECT ci.name FROM run r JOIN catalogue_item ci USING (item_id) WHERE r.run_id = a.run_id), 'Standalone'),
             'who', user_name(a.actor), 'run_id', a.run_id, 'proc_instance_id', NULL,
             'entity_id', run_entity_for(a.run_id, calendar_json.actor), 'entity_name', user_name(run_entity_for(a.run_id, calendar_json.actor)))
      FROM audit_log a
     WHERE a.actor = calendar_json.actor AND a.krama_id IS NULL
       AND a.action NOT IN ('Submitted','Reviewed','Agreed','Contested','Deadlock (Dropped)','Cancelled','Reopened')
       AND (a.at AT TIME ZONE 'Asia/Kolkata')::date BETWEEN p_from AND p_to
  ) s
$$;

-- History and audit: for the Requestor/Conductor and the super-user
CREATE FUNCTION audit_json(p_run uuid, actor uuid) RETURNS json LANGUAGE sql STABLE AS $$
  SELECT json_build_object('purpose', ci.name, 'label', run_label(r), 'version', k.version, 'date', r.started_on,
    'status', r.status, 'outcome', r.result, 'requestor_name', user_name(r.requestor_id), 'fy', r.fy,
    'rooms', (SELECT json_agg(json_build_object('name', name, 'type', kind) ORDER BY kind_rank(kind)) FROM room WHERE run_id = r.run_id),
    'events', (SELECT COALESCE(json_agg(json_build_object('at', to_char(a.at AT TIME ZONE 'Asia/Kolkata', 'DD Mon YYYY HH24:MI'),
                 'who', COALESCE(user_name(a.actor), 'System'), 'procedure', NULL, 'action', a.action, 'detail', a.detail)
                 ORDER BY a.at), '[]') FROM audit_log a WHERE a.run_id = r.run_id))
  FROM run r JOIN catalogue_item ci USING (item_id) JOIN krama k ON k.krama_id = r.krama_id
  WHERE r.run_id = p_run AND (r.requestor_id = actor OR is_super(actor))
$$;

-- Krama console: platform Kramas for the platform super-user; each entity's pool for its entity super-user
CREATE FUNCTION krama_json(k krama, actor uuid) RETURNS json LANGUAGE sql STABLE AS $$
  SELECT json_build_object(
    'krama_id', k.krama_id, 'code', k.code, 'name', k.name, 'owner_entity', k.owner_entity, 'owner_name', user_name(k.owner_entity),
    'ownership_type', k.ownership_type, 'pool_mark', k.pool_mark, 'status', k.status, 'version', k.version,
    'tag_kind', k.tag_kind, 'tag_domain', k.tag_domain, 'external', is_external(k.krama_id),
    'relationships', (SELECT COALESCE(json_agg(json_build_object('id', m.id, 'relationship', m.relationship, 'party_type', m.party_type,
                        'persona', pt.display_name, 'inherited', m.krama_id <> k.krama_id) ORDER BY m.relationship, pt.display_name), '[]')
                      FROM krama_relationship m JOIN persona_type pt USING (persona_type_id)
                     WHERE m.krama_id IN (k.krama_id, matrix_root(k.krama_id))),
    'lifetime_years', k.lifetime_years, 'what_changed', k.what_changed,
    'newer_platform_version', newer_platform_version(k.krama_id),
    'has_next_version', EXISTS (SELECT 1 FROM krama n WHERE n.previous_version = k.krama_id),
    'can_design', can_design(actor, k.krama_id),
    'rooms', (SELECT COALESCE(json_agg(json_build_object('room_template_id', room_template_id, 'kind', kind, 'label', label)
               ORDER BY kind_rank(kind)), '[]') FROM room_template WHERE krama_id = k.krama_id),
    'reports', (SELECT COALESCE(json_agg(json_build_object('report_id', report_id, 'name', name, 'question_text', question_text)), '[]')
                FROM report WHERE krama_id = k.krama_id),
    'stages', (SELECT COALESCE(json_agg(json_build_object('stage_id', s.stage_id, 'name', s.name, 'seq', s.seq, 'path', s.path,
        'expertise', expertise_json(s.stage_id, NULL, NULL), 'capabilities', caps_at(s.stage_id, NULL, NULL),
        'topics', (SELECT COALESCE(json_agg(json_build_object('topic_id', t.topic_id, 'name', t.name, 'seq', t.seq, 'path', t.path,
            'is_output', t.is_output, 'capabilities', caps_at(NULL, t.topic_id, NULL),
            'questions', (SELECT COALESCE(json_agg(json_build_object('question_id', q.question_id, 'text', q.text, 'seq', q.seq,
                'flow_option', q.flow_option, 'ask_in', q.ask_in, 'rules', q.rules, 'due_days', q.due_days,
                'setup_options', q.setup_options, 'setup_choices', q.setup_choices, 'setup_multi', q.setup_multi,
                'setup_columns', q.setup_columns, 'setup_limit', q.setup_limit, 'also_needs', q.also_needs,
                'capabilities', caps_at(NULL, NULL, q.question_id),
                'links', (SELECT COALESCE(json_agg(json_build_object('predecessor_id', l.predecessor_id, 'text', pq.text)), '[]')
                          FROM question_link l JOIN question pq ON pq.question_id = l.predecessor_id WHERE l.question_id = q.question_id))
              ORDER BY q.seq), '[]') FROM question q WHERE q.topic_id = t.topic_id))
          ORDER BY t.seq), '[]') FROM topic t WHERE t.stage_id = s.stage_id))
      ORDER BY s.seq), '[]') FROM stage s WHERE s.krama_id = k.krama_id))
$$;

CREATE FUNCTION console_json(actor uuid) RETURNS json LANGUAGE sql STABLE AS $$
  SELECT json_build_object(
    'is_super', is_super(actor),
    'entities', (SELECT COALESCE(json_agg(json_build_object('entity_id', l.company_user_id, 'name', user_name(l.company_user_id))), '[]')
                 FROM person_entity_link l WHERE l.person_id = actor AND l.is_entity_super_user),
    'kramas', (SELECT COALESCE(json_agg(krama_json(k, actor) ORDER BY k.owner_entity NULLS FIRST, k.name, k.version), '[]')
               FROM krama k
              WHERE (k.owner_entity IS NULL AND is_super(actor)) OR is_entity_super(actor, k.owner_entity)),
    'importable', (SELECT COALESCE(json_agg(json_build_object('krama_id', k.krama_id, 'name', k.name, 'version', k.version,
                    'ownership_type', k.ownership_type, 'tag_domain', k.tag_domain)), '[]')
                   FROM krama k WHERE k.owner_entity IS NULL AND k.status = 'Published'
                     AND k.ownership_type = 'Platform Built Entity Owned'
                     AND NOT EXISTS (SELECT 1 FROM krama n WHERE n.previous_version = k.krama_id AND n.status = 'Published')))
$$;

-- Catalogue: entity instances of the person's entities, with their library item, Dept/BUs and assigned Kramas;
-- Published Kramas an entity super-user can still assign; entities to pick as counterparty
CREATE FUNCTION catalogue_json(actor uuid) RETURNS json LANGUAGE sql STABLE AS $$
  SELECT json_build_object(
    'items', (SELECT COALESCE(json_agg(json_build_object('item_id', ci.item_id, 'name', ci.name, 'entity_id', ci.company_user_id,
                'entity_name', user_name(ci.company_user_id), 'can_edit', is_entity_super(actor, ci.company_user_id),
                'library', (SELECT json_build_object('kind', li.kind, 'name', li.name, 'metadata', li.metadata,
                              'seller', (SELECT display_name FROM persona_type WHERE persona_type_id = li.seller_persona_type_id),
                              'buyer', (SELECT display_name FROM persona_type WHERE persona_type_id = li.buyer_persona_type_id))
                            FROM library_item li WHERE li.library_item_id = ci.library_item_id),
                'library_item_id', ci.library_item_id, 'visibility', visibility_label(ci), 'release', ci.release,
                'variants', (SELECT string_agg(name, ', ' ORDER BY seq) FROM catalogue_variant WHERE item_id = ci.item_id),
                'pricing', (SELECT pricing_type || COALESCE(' ' || price, '') || ' ' || tax_mode FROM catalogue_variant WHERE item_id = ci.item_id ORDER BY seq LIMIT 1),
                'offering', (SELECT name FROM dept_bu WHERE dept_bu_id = ci.host_dept_bu_id),
                'dept_bus', (SELECT COALESCE(json_agg(json_build_object('dept_bu_id', d.dept_bu_id, 'name', d.name) ORDER BY d.name), '[]')
                             FROM dept_bu d WHERE d.company_user_id = ci.company_user_id),
                'has_external', EXISTS (SELECT 1 FROM catalogue_item_krama x WHERE x.item_id = ci.item_id AND is_external(x.krama_id)),
                'has_internal', EXISTS (SELECT 1 FROM catalogue_item_krama x WHERE x.item_id = ci.item_id AND NOT is_external(x.krama_id)),
                'kramas', (SELECT COALESCE(json_agg(json_build_object('krama_id', k.krama_id, 'name', k.name, 'version', k.version,
                             'ownership_type', k.ownership_type, 'external', is_external(k.krama_id),
                             'relationships', (SELECT COALESCE(json_agg(DISTINCT m.relationship || ' · ' || pt.display_name), '[]')
                                                 FROM krama_relationship m JOIN persona_type pt USING (persona_type_id)
                                                WHERE m.krama_id IN (k.krama_id, matrix_root(k.krama_id))))
                             ORDER BY k.name), '[]')
                           FROM catalogue_item_krama x JOIN krama k USING (krama_id) WHERE x.item_id = ci.item_id))
              ORDER BY ci.name), '[]')
              FROM catalogue_item ci WHERE is_member_of_entity(actor, ci.company_user_id)),
    'addable', (SELECT COALESCE(json_agg(json_build_object('krama_id', k.krama_id, 'name', k.name, 'version', k.version,
                  'entity_id', e.company_user_id, 'entity_name', user_name(e.company_user_id), 'ownership_type', k.ownership_type)), '[]')
                FROM krama k JOIN person_entity_link e ON e.person_id = actor AND e.is_entity_super_user
               WHERE k.status = 'Published'
                 AND (k.owner_entity = e.company_user_id OR (k.owner_entity IS NULL AND k.ownership_type = 'Platform Built Platform Owned'))),
    'companies', (SELECT COALESCE(json_agg(json_build_object('user_id', u.user_id, 'name', u.name,
                    'persona', (SELECT pt.display_name FROM company c JOIN persona_type pt USING (persona_type_id) WHERE c.user_id = u.user_id))
                    ORDER BY u.name), '[]')
                  FROM users u WHERE u.user_type = 'Company'))
$$;

-- Which Kramas of an item apply for this relationship and counterparty
CREATE FUNCTION resolve_json(p_item uuid, p_relationship text, p_counterparty uuid) RETURNS json LANGUAGE sql STABLE AS $$
  SELECT COALESCE(json_agg(json_build_object('krama_id', k.krama_id, 'name', k.name, 'version', k.version) ORDER BY k.name), '[]')
    FROM krama k WHERE k.krama_id IN (SELECT resolve_kramas(p_item, p_relationship, p_counterparty))
$$;

-- ---------- screens shaped like the Figma ----------

CREATE FUNCTION side_of(rel text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN rel IN ('Pre-vendor','Vendor') THEN 'BUY' WHEN rel IN ('Pre-client','Client') THEN 'SELL' ELSE 'INTERNAL' END
$$;

-- Business: the entities the person belongs to
CREATE FUNCTION business_json(actor uuid) RETURNS json LANGUAGE sql STABLE AS $$
  SELECT json_build_object(
    'entities', COALESCE(json_agg(json_build_object(
       'entity_id', l.company_user_id, 'name', user_name(l.company_user_id),
       'sub_type', (SELECT ct.sub_type FROM company c JOIN company_type ct USING (company_type_id) WHERE c.user_id = l.company_user_id),
       'persona', (SELECT pt.display_name FROM company c JOIN persona_type pt USING (persona_type_id) WHERE c.user_id = l.company_user_id),
       'operational', EXISTS (SELECT 1 FROM company c WHERE c.user_id = l.company_user_id AND c.persona_type_id IS NOT NULL)
                      AND EXISTS (SELECT 1 FROM dept_bu d WHERE d.company_user_id = l.company_user_id),
       'is_entity_super', l.is_entity_super_user) ORDER BY user_name(l.company_user_id)), '[]'))
  FROM person_entity_link l WHERE l.person_id = actor
$$;

-- Entity Home: questions and Standalone tasks in this entity, each with its quadrant
CREATE FUNCTION entity_home_json(actor uuid, p_entity uuid) RETURNS json LANGUAGE sql STABLE AS $$
  SELECT COALESCE(json_agg(z ORDER BY z->>'due_date' NULLS LAST), '[]') FROM (
    SELECT json_build_object('kind', 'question', 'id', x.qr_id, 'run_id', x.run_id, 'ref', r.instance_code, 'lane', 'workflow',
             'title', q.text, 'context', ci.name || COALESCE(' · ' || user_name(r.counterparty), ''),
             'state', x.answer_state, 'quadrant', x.quadrant, 'due_date', x.due_date,
             'with_me', is_with(x.qr_id, actor), 'room', rm.kind) AS z
      FROM question_run x JOIN question q USING (question_id) JOIN run r USING (run_id)
      JOIN catalogue_item ci USING (item_id) JOIN room rm ON rm.room_id = x.room_id
     WHERE (r.company_user_id = p_entity OR r.counterparty = p_entity) AND x.status = 'Open' AND r.locked_at IS NULL
       AND NOT (SELECT locked FROM qr_ctx(x.qr_id)) AND can_see_qr(x.qr_id, actor)
    UNION ALL
    SELECT json_build_object('kind', 'standalone', 'id', st.task_id, 'run_id', NULL, 'ref', 'TSK-' || upper(left(st.task_id::text, 4)),
             'lane', 'Standalone', 'title', st.title, 'context', COALESCE(st.notes, 'just you'), 'state', 'Open',
             'quadrant', st.quadrant, 'due_date', st.due_date, 'with_me', true, 'room', 'PR')
      FROM standalone_task st WHERE st.owner_id = actor AND st.company_user_id = p_entity AND st.status = 'Open'
  ) s
$$;

-- Task list: runs (workflow lane) and the person's Standalone tasks in this entity
CREATE FUNCTION tasks_json(actor uuid, p_entity uuid) RETURNS json LANGUAGE sql STABLE AS $$
  SELECT COALESCE(json_agg(z ORDER BY z->>'status' DESC, z->>'next_due' NULLS LAST), '[]') FROM (
    SELECT json_build_object('kind', 'run', 'id', r.run_id, 'ref', run_label(r), 'title', ci.name, 'lane', 'workflow',
             -- the counterparty sees the mirror side and the other entity's name
             'side', CASE WHEN r.counterparty = p_entity THEN CASE side_of(r.relationship) WHEN 'BUY' THEN 'SELL' WHEN 'SELL' THEN 'BUY' ELSE 'INTERNAL' END
                          ELSE side_of(r.relationship) END,
             'counterparty', CASE WHEN r.counterparty = p_entity THEN user_name(r.company_user_id) ELSE user_name(r.counterparty) END,
             'status', CASE WHEN r.locked_at IS NOT NULL THEN 'Closed' ELSE 'Open' END, 'result', r.result,
             'open_lines', (SELECT count(*) FROM question_run WHERE run_id = r.run_id AND status = 'Open'),
             'total_lines', (SELECT count(*) FROM question_run WHERE run_id = r.run_id),
             'next_due', (SELECT min(due_date) FROM question_run WHERE run_id = r.run_id AND status = 'Open'),
             'quadrant', (SELECT x.quadrant FROM question_run x WHERE x.run_id = r.run_id AND x.status = 'Open'
                           ORDER BY CASE x.quadrant WHEN 'Do now' THEN 1 WHEN 'Do later' THEN 2 WHEN 'Delegate' THEN 3 ELSE 4 END LIMIT 1)) AS z
      FROM run r JOIN catalogue_item ci USING (item_id)
     WHERE (r.company_user_id = p_entity OR r.counterparty = p_entity) AND r.run_id IN (SELECT visible_runs(actor))
    UNION ALL
    SELECT json_build_object('kind', 'standalone', 'id', st.task_id, 'ref', 'TSK-' || upper(left(st.task_id::text, 4)), 'title', st.title,
             'lane', 'Standalone', 'side', 'INTERNAL', 'counterparty', NULL,
             'status', CASE WHEN st.status = 'Done' THEN 'Closed' ELSE 'Open' END, 'result', CASE WHEN st.status = 'Done' THEN 'Done' END,
             'open_lines', CASE WHEN st.status = 'Open' THEN 1 ELSE 0 END, 'total_lines', 1,
             'next_due', CASE WHEN st.status = 'Open' THEN st.due_date END, 'quadrant', st.quadrant, 'notes', st.notes)
      FROM standalone_task st WHERE st.owner_id = actor AND st.company_user_id = p_entity
  ) s
$$;

-- Vendors: entities this entity works with on the buy side
CREATE FUNCTION vendors_json(actor uuid, p_entity uuid) RETURNS json LANGUAGE sql STABLE AS $$
  SELECT COALESCE(json_agg(json_build_object('entity_id', v.cp, 'name', user_name(v.cp), 'relationship', v.rel,
           'persona', (SELECT pt.display_name FROM company c JOIN persona_type pt USING (persona_type_id) WHERE c.user_id = v.cp),
           'runs', v.n, 'open', v.open) ORDER BY user_name(v.cp)), '[]')
  FROM (SELECT r.counterparty cp, max(r.relationship) rel, count(*) n, count(*) FILTER (WHERE r.locked_at IS NULL) open
          FROM run r WHERE r.company_user_id = p_entity AND r.relationship IN ('Pre-vendor','Vendor')
           AND is_member_of_entity(actor, p_entity) GROUP BY r.counterparty) v
$$;

CREATE FUNCTION personal_tasks_json(actor uuid) RETURNS json LANGUAGE sql STABLE AS $$
  SELECT COALESCE(json_agg(json_build_object('task_id', task_id, 'kind', kind, 'requested_by', user_name(requested_by),
           'title', title, 'purpose', purpose, 'due_date', due_date, 'quadrant', quadrant, 'status', status,
           'done_on', to_char(done_at AT TIME ZONE 'Asia/Kolkata', 'YYYY-MM-DD'))
           ORDER BY CASE quadrant WHEN 'Do now' THEN 1 WHEN 'Do later' THEN 2 WHEN 'Delegate' THEN 3 ELSE 4 END, due_date NULLS LAST), '[]')
    FROM personal_task WHERE owner_id = actor
$$;


-- One room's own space: its registries (entries, plus files attached in its answers), its calendar and its chat
CREATE FUNCTION room_json(p_room uuid, actor uuid) RETURNS json LANGUAGE sql STABLE AS $$
  SELECT CASE WHEN NOT room_open_to(p_room, actor) THEN NULL ELSE json_build_object(
    'room_id', rm.room_id, 'name', rm.name, 'kind', rm.kind,
    'registries', (SELECT COALESCE(json_agg(json_build_object('registry_id', g.registry_id, 'name', g.name, 'description', g.description, 'holds', g.holds,
        'entries', (SELECT COALESCE(json_agg(json_build_object('entry_id', e.entry_id, 'kind', e.kind, 'title', e.title, 'on_date', e.on_date,
                       'stage', (SELECT name FROM stage WHERE stage_id = e.stage_id), 'status', e.status,
                       'source', (SELECT name FROM room WHERE room_id = e.source_room_id), 'by', user_name(e.by_person)) ORDER BY e.at), '[]')
                    FROM registry_entry e WHERE e.registry_id = g.registry_id)) ORDER BY g.name), '[]')
      FROM registry g WHERE g.room_id = rm.room_id),
    'answer_files', (SELECT COALESCE(json_agg(json_build_object('file', f.file, 'mobility', f.mobility, 'question', f.text, 'stage', f.stage,
                       'status', f.status) ORDER BY f.text), '[]') FROM (
        SELECT COALESCE(x.answer_data->>'file', x.answer_data->'attachment'->>'file') AS file,
               COALESCE(x.answer_data->>'mobility', x.answer_data->'attachment'->>'mobility') AS mobility,
               q.text, s.name AS stage, CASE WHEN x.answer_state = 'Agreed' THEN 'Approved' WHEN x.status = 'Closed' THEN 'Closed' ELSE 'Open' END AS status
          FROM question_run x JOIN question q USING (question_id) JOIN topic t USING (topic_id) JOIN stage s USING (stage_id)
         WHERE x.room_id = rm.room_id AND COALESCE(x.answer_data->>'file', x.answer_data->'attachment'->>'file') IS NOT NULL) f),
    'calendar', (SELECT COALESCE(json_agg(c ORDER BY c->>'date'), '[]') FROM (
        SELECT json_build_object('date', x.due_date, 'kind', 'Due', 'title', q.text) c
          FROM question_run x JOIN question q USING (question_id)
         WHERE x.room_id = rm.room_id AND x.status = 'Open' AND x.answer_state NOT IN ('Agreed','Deadlock')
        UNION ALL
        SELECT json_build_object('date', e.on_date, 'kind', 'Event', 'title', e.title)
          FROM registry_entry e JOIN registry g USING (registry_id) WHERE g.room_id = rm.room_id AND e.kind = 'Event') z),
    'messages', (SELECT COALESCE(json_agg(json_build_object('by', user_name(m.by_person), 'mine', m.by_person = actor, 'body', m.body,
                    'mention', (SELECT q.text FROM question_run x JOIN question q USING (question_id) WHERE x.qr_id = m.mention_qr),
                    'mention_qr', m.mention_qr, 'at', to_char(m.at AT TIME ZONE 'Asia/Kolkata', 'DD Mon HH24:MI')) ORDER BY m.at), '[]')
      FROM room_message m WHERE m.room_id = rm.room_id),
    'sees', CASE rm.kind WHEN 'ER' THEN 'Seen by both sides' WHEN 'IR' THEN 'Seen by this entity''s people in the room' ELSE 'Seen only by this Dept/BU' END
  ) END
  FROM room rm WHERE rm.room_id = p_room
$$;

CREATE FUNCTION capabilities_json() RETURNS json LANGUAGE sql STABLE AS $$
  SELECT COALESCE(json_agg(json_build_object('code', code, 'name', name, 'what', what, 'boundaries', boundaries) ORDER BY seq), '[]') FROM capability
$$;


-- ---------- Catalogue screens ----------

CREATE FUNCTION catalogue_row(ci catalogue_item) RETURNS json LANGUAGE sql STABLE AS $$
  SELECT json_build_object('item_id', ci.item_id, 'code', ci.catalogue_code, 'name', ci.name, 'item_type', ci.item_type,
    'catalogue', ci.catalogue, 'visibility', visibility_label(ci), 'release', ci.release, 'review', ci.review,
    'entity_id', ci.company_user_id, 'entity_name', user_name(ci.company_user_id),
    'variants', (SELECT count(*) FROM catalogue_variant WHERE item_id = ci.item_id))
$$;

-- Owned: the entity's own items. Borrowed: its vendors' published items shared with it.
-- Pickers for "+ Add item": the domain tree and the platform library.
CREATE FUNCTION entity_catalogue_json(actor uuid, p_entity uuid) RETURNS json LANGUAGE sql STABLE AS $$
  SELECT CASE WHEN NOT is_member_of_entity(actor, p_entity) THEN NULL ELSE json_build_object(
    'can_edit', can_edit_catalogue(actor, p_entity),
    'owned', (SELECT COALESCE(json_agg(catalogue_row(ci) ORDER BY ci.catalogue_code), '[]') FROM catalogue_item ci WHERE ci.company_user_id = p_entity),
    'borrowed', (SELECT COALESCE(json_agg(catalogue_row(ci) ORDER BY user_name(ci.company_user_id), ci.name), '[]')
                   FROM catalogue_item ci WHERE ci.company_user_id <> p_entity AND borrowed_by(ci, p_entity)),
    'domains', (SELECT COALESCE(json_agg(json_build_object('domain_id', d.domain_id, 'catalogue', d.catalogue, 'name', d.name,
                  'personas', (SELECT COALESCE(json_agg(json_build_object('domain_persona_id', p.domain_persona_id, 'name', p.name, 'metadata', p.metadata) ORDER BY p.name), '[]')
                                 FROM domain_persona p WHERE p.domain_id = d.domain_id)) ORDER BY d.catalogue, d.name), '[]') FROM catalogue_domain d),
    'library', (SELECT COALESCE(json_agg(json_build_object('library_item_id', li.library_item_id, 'kind', li.kind, 'name', li.name,
                  'metadata', li.metadata, 'domain_persona_id', li.domain_persona_id) ORDER BY li.kind, li.name), '[]') FROM library_item li)) END
$$;

-- One item, with everything its side menu shows
CREATE FUNCTION catalogue_item_json(actor uuid, p_item uuid) RETURNS json LANGUAGE sql STABLE AS $$
  SELECT CASE WHEN NOT can_see_item(actor, ci) THEN NULL ELSE json_build_object(
    'item_id', ci.item_id, 'code', ci.catalogue_code, 'name', ci.name, 'item_type', ci.item_type, 'catalogue', ci.catalogue,
    'release', ci.release, 'review', ci.review, 'entity_id', ci.company_user_id, 'entity_name', user_name(ci.company_user_id),
    'owned', is_member_of_entity(actor, ci.company_user_id), 'can_edit', COALESCE(can_edit_item(actor, ci.item_id), false),
    'domain', (SELECT d.name FROM domain_persona p JOIN catalogue_domain d USING (domain_id) WHERE p.domain_persona_id = ci.domain_persona_id),
    'domain_persona', (SELECT json_build_object('name', p.name, 'metadata', p.metadata) FROM domain_persona p WHERE p.domain_persona_id = ci.domain_persona_id),
    'library', (SELECT json_build_object('name', li.name, 'kind', li.kind, 'metadata', li.metadata) FROM library_item li WHERE li.library_item_id = ci.library_item_id),
    'library_use', ci.library_use,
    'visibility', json_build_object('label', visibility_label(ci), 'scope', ci.visibility_scope, 'audience', ci.visibility_audience,
                   'reach', ci.visibility_reach, 'names', to_json(ci.visibility_names), 'host_dept_bu_id', ci.host_dept_bu_id),
    'content', json_build_object('title', ci.content_title, 'main_image', ci.main_image, 'blocks', ci.content_blocks),
    'marketing', json_build_object('landing_page', ci.landing_page, 'landing_status', ci.landing_status, 'brand_name', ci.brand_name,
                  'category', ci.category, 'sub_category', ci.sub_category, 'competitors', ci.competitors),
    'variants', (SELECT COALESCE(json_agg(json_build_object('variant_id', v.variant_id, 'name', v.name, 'pricing_type', v.pricing_type, 'price', v.price,
                   'tax_mode', v.tax_mode, 'hsn_sac', v.hsn_sac, 'gst_rate', v.gst_rate, 'quotation_wording', v.quotation_wording,
                   'invoice_wording', v.invoice_wording, 'offer_kind', v.offer_kind, 'offer_amount', v.offer_amount, 'offer_for', v.offer_for,
                   'offer_names', to_json(v.offer_names), 'offer_until', v.offer_until, 'promo', v.promo,
                   'journey', (SELECT COALESCE(json_agg(json_build_object('step', j.step, 'krama_id', j.krama_id,
                                 'krama', (SELECT name || ' v' || version FROM krama WHERE krama_id = j.krama_id))), '[]')
                                 FROM catalogue_journey_step j WHERE j.variant_id = v.variant_id),
                   'dependencies', (SELECT COALESCE(json_agg(json_build_object('dependency_id', d.dependency_id, 'level', d.level, 'timing', d.timing,
                                     'done_outside', d.done_outside,
                                     'name', COALESCE((SELECT name || ' v' || version FROM krama WHERE krama_id = d.krama_id),
                                                      (SELECT catalogue_code || ' · ' || name FROM catalogue_item WHERE item_id = d.dep_item_id)))
                                     ORDER BY d.timing DESC, d.level), '[]')
                                    FROM catalogue_dependency d WHERE d.variant_id = v.variant_id))
                   ORDER BY v.seq), '[]') FROM catalogue_variant v WHERE v.item_id = ci.item_id),
    'seats', (SELECT COALESCE(json_agg(json_build_object('catalogue_seat_id', s.catalogue_seat_id, 'seat', s.seat, 'side', s.side,
                'name', COALESCE((SELECT name FROM dept_bu WHERE dept_bu_id = s.dept_bu_id), user_name(s.party_id)),
                'vendor_item', (SELECT catalogue_code || ' · ' || name FROM catalogue_item WHERE item_id = s.vendor_item_id))
                ORDER BY array_position(ARRAY['Buyer','Seller','Fulfiller','Assurer','Representation'], s.seat)), '[]')
              FROM catalogue_seat s WHERE s.item_id = ci.item_id),
    'kramas', (SELECT COALESCE(json_agg(json_build_object('krama_id', k.krama_id, 'name', k.name, 'version', k.version,
                 'external', is_external(k.krama_id), 'ownership_type', k.ownership_type,
                 'runs', (SELECT count(*) FROM run WHERE item_id = ci.item_id AND krama_id = k.krama_id),
                 'stages', (SELECT COALESCE(json_agg(json_build_object('name', st.name,
                              'topics', (SELECT COALESCE(json_agg(json_build_object('name', t.name,
                                           'questions', (SELECT count(*) FROM question q WHERE q.topic_id = t.topic_id)) ORDER BY t.seq), '[]')
                                           FROM topic t WHERE t.stage_id = st.stage_id)) ORDER BY st.seq), '[]')
                             FROM stage st WHERE st.krama_id = k.krama_id),
                 'reports', (SELECT COALESCE(json_agg(json_build_object('name', rp.name, 'question', rp.question_text) ORDER BY rp.name), '[]')
                               FROM report rp WHERE rp.krama_id = k.krama_id)) ORDER BY k.name), '[]')
               FROM catalogue_item_krama x JOIN krama k USING (krama_id) WHERE x.item_id = ci.item_id),
    'runs', (SELECT json_build_object('total', count(*), 'open', count(*) FILTER (WHERE r.status = 'Open'),
               'fulfilled', count(*) FILTER (WHERE r.result = 'Fulfilled'), 'unfulfilled', count(*) FILTER (WHERE r.result = 'Unfulfilled'),
               'by_relationship', (SELECT COALESCE(json_agg(json_build_object('relationship', z.relationship, 'n', z.n) ORDER BY z.n DESC), '[]')
                                     FROM (SELECT relationship, count(*) n FROM run WHERE item_id = ci.item_id GROUP BY relationship) z),
               'last', max(r.started_on))
             FROM run r WHERE r.item_id = ci.item_id),
    -- Pickers (the item's own entity only)
    'dept_bus', (SELECT COALESCE(json_agg(json_build_object('id', d.dept_bu_id, 'name', d.name) ORDER BY d.name), '[]')
                 FROM dept_bu d WHERE d.company_user_id = ci.company_user_id),
    'entities', (SELECT COALESCE(json_agg(json_build_object('id', u.user_id, 'name', u.name,
                   'relationship', (SELECT max(relationship) FROM run WHERE company_user_id = ci.company_user_id AND counterparty = u.user_id
                                      AND relationship IN ('Pre-client','Client','Pre-vendor','Vendor')),
                   'items', (SELECT COALESCE(json_agg(json_build_object('id', v.item_id, 'name', v.catalogue_code || ' · ' || v.name) ORDER BY v.name), '[]')
                               FROM catalogue_item v WHERE v.company_user_id = u.user_id AND v.review = 'Success')) ORDER BY u.name), '[]')
                 FROM users u WHERE u.user_type = 'Company' AND u.user_id <> ci.company_user_id),
    'assignable', (SELECT COALESCE(json_agg(json_build_object('id', k.krama_id, 'name', k.name || ' v' || k.version,
                     'external', is_external(k.krama_id), 'used_on', (SELECT string_agg(o.name, ', ' ORDER BY o.name)
                        FROM catalogue_item_krama y JOIN catalogue_item o USING (item_id) WHERE y.krama_id = k.krama_id AND o.company_user_id = ci.company_user_id))
                     ORDER BY k.name), '[]')
                   FROM krama k WHERE k.status = 'Published'
                     AND (k.owner_entity = ci.company_user_id OR (k.owner_entity IS NULL AND k.ownership_type = 'Platform Built Platform Owned'))
                     AND NOT EXISTS (SELECT 1 FROM catalogue_item_krama y WHERE y.item_id = ci.item_id AND y.krama_id = k.krama_id)),
    'pick_kramas', (SELECT COALESCE(json_agg(json_build_object('id', k.krama_id, 'name', k.name || ' v' || k.version, 'tag', k.tag_domain) ORDER BY k.name), '[]')
                    FROM krama k WHERE k.status = 'Published'
                      AND (k.owner_entity = ci.company_user_id OR (k.owner_entity IS NULL AND k.ownership_type = 'Platform Built Platform Owned'))),
    'pick_items', (SELECT COALESCE(json_agg(json_build_object('id', o.item_id, 'name', o.catalogue_code || ' · ' || o.name, 'release', o.release) ORDER BY o.name), '[]')
                   FROM catalogue_item o WHERE o.company_user_id = ci.company_user_id AND o.item_id <> ci.item_id
                     AND o.release IN ('Beta','General Availability'))) END
  FROM catalogue_item ci WHERE ci.item_id = p_item
$$;
