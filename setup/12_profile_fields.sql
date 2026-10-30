-- =====================================================================================
-- The remaining framework fields: Domain-specific knowledge on the Domain Profile;
-- Areas of operation and Business interests on the Entity Profile. All optional.
-- =====================================================================================
ALTER TABLE domain_profile ADD COLUMN knowledge text[] NOT NULL DEFAULT '{}';
ALTER TABLE company ADD COLUMN areas_of_operation text[] NOT NULL DEFAULT '{}',
                    ADD COLUMN business_interests text[] NOT NULL DEFAULT '{}';

CREATE OR REPLACE FUNCTION api_save_domain_profile(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
BEGIN
  IF NOT is_super(actor) THEN RAISE EXCEPTION 'Only the platform super-user defines domain profiles'; END IF;
  INSERT INTO domain_profile (domain_id, objectives, terminology, regulations, typical_workflows, controls, compliance_requirements, knowledge)
  VALUES ((b->>'domain_id')::uuid, j(b, 'objectives'), lines(b->>'terminology'), lines(b->>'regulations'), lines(b->>'typical_workflows'),
          lines(b->>'controls'), j(b, 'compliance_requirements'), lines(b->>'knowledge'))
  ON CONFLICT (domain_id) DO UPDATE SET objectives = EXCLUDED.objectives, terminology = EXCLUDED.terminology, regulations = EXCLUDED.regulations,
     typical_workflows = EXCLUDED.typical_workflows, controls = EXCLUDED.controls, compliance_requirements = EXCLUDED.compliance_requirements,
     knowledge = EXCLUDED.knowledge;
  RETURN json_build_object('ok', true);
END $$;

CREATE OR REPLACE FUNCTION api_entity_profile(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql AS $$
DECLARE e uuid := (b->>'entity_id')::uuid;
BEGIN
  IF b ? 'save' THEN
    PERFORM need_admin(actor, e);
    UPDATE company SET objectives = j(b->'save', 'objectives'), capabilities = lines(b->'save'->>'capabilities'),
           areas_of_operation = lines(b->'save'->>'areas_of_operation'), business_interests = lines(b->'save'->>'business_interests')
     WHERE user_id = e;
  ELSE PERFORM need_member(actor, e);
  END IF;
  RETURN (SELECT json_build_object('objectives', objectives, 'capabilities', capabilities, 'areas_of_operation', areas_of_operation,
                                   'business_interests', business_interests) FROM company WHERE user_id = e);
END $$;

CREATE OR REPLACE FUNCTION domain_brief(d uuid) RETURNS json LANGUAGE sql STABLE AS $$
  SELECT json_build_object('domain_id', cd.domain_id, 'name', cd.catalogue || ' › ' || cd.name, 'objectives', dp.objectives,
           'regulations', dp.regulations, 'controls', dp.controls, 'compliance_requirements', dp.compliance_requirements, 'knowledge', dp.knowledge)
    FROM catalogue_domain cd LEFT JOIN domain_profile dp USING (domain_id) WHERE cd.domain_id = d
$$;

-- The task's context now also carries the entity's areas of operation and business interests
CREATE OR REPLACE FUNCTION entity_brief(e uuid) RETURNS json LANGUAGE sql STABLE AS $$
  SELECT json_build_object('name', user_name(c.user_id), 'persona', persona_path(c.persona_type_id), 'objectives', c.objectives, 'capabilities', c.capabilities,
                           'areas_of_operation', c.areas_of_operation, 'business_interests', c.business_interests)
    FROM company c WHERE c.user_id = e
$$;

-- Samples
UPDATE company SET areas_of_operation = '{Bengaluru,Mysuru}', business_interests = '{Private-label stationery,Second store}'
 WHERE user_id = '11111111-0000-0000-0000-000000000012';
UPDATE domain_profile SET knowledge = '{Claims need an original or digital receipt,Reimbursement follows the approved expense policy}'
 WHERE domain_id = 'd0000000-0000-0000-0000-000000000004';
