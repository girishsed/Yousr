-- An entity can be connected to only if someone there can accept: it has at least one entity admin.
-- Entities without one never show in Discover / Connect / client search, and are never linked by name.
CREATE FUNCTION can_accept(e uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT EXISTS (SELECT 1 FROM person_entity_link WHERE company_user_id = e AND is_entity_super_user)
$$;

CREATE OR REPLACE FUNCTION api_discover(actor uuid, b jsonb) RETURNS json LANGUAGE plpgsql STABLE AS $$
DECLARE e uuid := NULLIF(b->>'entity_id', '')::uuid; q text := '%' || lower(coalesce(j(b, 'q'), '')) || '%';
BEGIN
  PERFORM need(actor);
  RETURN (SELECT COALESCE(json_agg(json_build_object('entity_id', u.user_id, 'name', u.name, 'persona', pt.display_name,
            'connection', (SELECT state FROM entity_connection c WHERE e IS NOT NULL AND ((c.from_entity = e AND c.to_entity = u.user_id) OR (c.from_entity = u.user_id AND c.to_entity = e)) AND failure IS NULL LIMIT 1),
            'items', (SELECT COALESCE(json_agg(json_build_object('name', ci.name, 'type', ci.item_type)), '[]')
                        FROM catalogue_item ci WHERE ci.company_user_id = u.user_id AND ci.visibility_audience = 'Discover and Connect'))
            ORDER BY u.name), '[]')
            FROM users u JOIN company co ON co.user_id = u.user_id LEFT JOIN persona_type pt ON pt.persona_type_id = co.persona_type_id
           WHERE u.user_type = 'Company' AND u.user_id IS DISTINCT FROM e AND can_accept(u.user_id)
             AND (lower(u.name) LIKE q OR lower(coalesce(pt.display_name, '')) LIKE q));
END $$;

-- Connection invites and client listings reach only entities that can accept
CREATE OR REPLACE FUNCTION refuse_unreachable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.to_entity IS NOT NULL AND NOT can_accept(NEW.to_entity) THEN
    IF NEW.relationship IN ('Client','Pre-client') AND NEW.state = 'Pending' THEN
      NEW.to_entity := NULL; NEW.state := 'Standalone';            -- kept as a listed client until someone can accept
    ELSE
      RAISE EXCEPTION '% has nobody who can accept a connection yet', NEW.to_name;
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER refuse_unreachable BEFORE INSERT ON entity_connection FOR EACH ROW EXECUTE FUNCTION refuse_unreachable();

-- Sample: an admin for Orbit IT Services, so it can accept
INSERT INTO users (user_id, name, personal_email, user_type, compane_id, identity_verified)
VALUES ('11111111-0000-0000-0000-000000000039', 'Nikhil Joshi', 'nikhil.joshi@example.com', 'Individual', 'CMP-' || upper(substr(md5('nikhil'), 1, 6)), true);
INSERT INTO person_entity_link (person_id, company_user_id, dept_bu_id, is_full_time, is_entity_super_user, work_email, designation, sits, employer_approved)
SELECT '11111111-0000-0000-0000-000000000039', u.user_id,
       (SELECT dept_bu_id FROM dept_bu WHERE company_user_id = u.user_id ORDER BY (name = 'Operations') DESC, name LIMIT 1),
       true, true, 'nikhil@orbit.example.com', 'Director', 'Admin above Dept/BU head', true
  FROM users u WHERE u.name = 'Orbit IT Services';
INSERT INTO personal_document (owner_id, kind, status, at)
SELECT '11111111-0000-0000-0000-000000000039', k, CASE WHEN k = 'National ID' THEN 'Verified' ELSE 'Not connected' END, CASE WHEN k = 'National ID' THEN clock_timestamp() END
  FROM unnest(ARRAY['National ID','Tax ID','Passport']) k;
