-- A vendor and client are related by a task already run between them, or by an accepted (Connected) connection:
-- the client listed the other as Vendor, or the vendor listed the other as Client and the client accepted.
-- A pending invite does not count until the counterparty validates it.
CREATE OR REPLACE FUNCTION is_vendor_of(v uuid, e uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT EXISTS (SELECT 1 FROM run WHERE company_user_id = e AND counterparty = v AND relationship IN ('Pre-vendor','Vendor'))
      OR EXISTS (SELECT 1 FROM entity_connection c WHERE c.state = 'Connected' AND c.failure IS NULL
                   AND ((c.from_entity = e AND c.to_entity = v AND c.relationship IN ('Vendor','Pre-vendor'))
                     OR (c.from_entity = v AND c.to_entity = e AND c.relationship IN ('Client','Pre-client'))))
$$;
