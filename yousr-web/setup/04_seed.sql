-- Demo data for FRD v3.0: masters, one platform Krama imported and customised by an entity, one run in progress

INSERT INTO expertise (expertise_id, name, role, purpose) VALUES
 ('e0000000-0000-0000-0000-000000000001','Financial Advisor','Advises on financial decisions and approvals','Makes sure spending and payments fit the business''s financial plan'),
 ('e0000000-0000-0000-0000-000000000002','CA','Reviews accounts, tax and statutory compliance','Gives assurance that records and filings are correct'),
 ('e0000000-0000-0000-0000-000000000003','Engineer','Builds, checks and signs off technical work','Confirms that delivered work meets the specification'),
 ('e0000000-0000-0000-0000-000000000004','Accountant','Records transactions and prepares accounts','Keeps books accurate and supporting files complete');

INSERT INTO company_type (company_type_id, sub_type, structure) VALUES
 ('c0000000-0000-0000-0000-000000000001','Sole proprietor','Functional'),
 ('c0000000-0000-0000-0000-000000000002','Partnership firm','Functional'),
 ('c0000000-0000-0000-0000-000000000003','Pvt Ltd','Business Unit'),
 ('c0000000-0000-0000-0000-000000000004','LLP','Functional'),
 ('c0000000-0000-0000-0000-000000000005','Public Ltd','Business Unit'),
 ('c0000000-0000-0000-0000-000000000006','Trust','Functional');

INSERT INTO company_type_dept_bu (company_type_id, name) VALUES
 ('c0000000-0000-0000-0000-000000000001','Finance'), ('c0000000-0000-0000-0000-000000000001','Operations'),
 ('c0000000-0000-0000-0000-000000000002','Finance'), ('c0000000-0000-0000-0000-000000000002','Operations'),
 ('c0000000-0000-0000-0000-000000000003','Finance'), ('c0000000-0000-0000-0000-000000000003','Sales'), ('c0000000-0000-0000-0000-000000000003','Operations'),
 ('c0000000-0000-0000-0000-000000000004','Finance'), ('c0000000-0000-0000-0000-000000000004','Operations'),
 ('c0000000-0000-0000-0000-000000000005','Finance'), ('c0000000-0000-0000-0000-000000000005','Sales'), ('c0000000-0000-0000-0000-000000000005','Operations'),
 ('c0000000-0000-0000-0000-000000000006','Finance'), ('c0000000-0000-0000-0000-000000000006','Operations');

INSERT INTO role_definition (company_type_id, name, description) VALUES
 ('c0000000-0000-0000-0000-000000000001','Proprietor','Owns and runs the business'),
 ('c0000000-0000-0000-0000-000000000001','Executive','Carries out day-to-day work'),
 ('c0000000-0000-0000-0000-000000000002','Partner','A partner in the firm'),
 ('c0000000-0000-0000-0000-000000000002','Manager','Manages a Dept/BU'),
 ('c0000000-0000-0000-0000-000000000002','Executive','Carries out day-to-day work'),
 ('c0000000-0000-0000-0000-000000000003','Director','A director of the company'),
 ('c0000000-0000-0000-0000-000000000003','Manager','Manages a Dept/BU'),
 ('c0000000-0000-0000-0000-000000000003','Executive','Carries out day-to-day work'),
 ('c0000000-0000-0000-0000-000000000004','Designated Partner','A designated partner of the LLP'),
 ('c0000000-0000-0000-0000-000000000004','Manager','Manages a Dept/BU'),
 ('c0000000-0000-0000-0000-000000000005','Director','A director of the company'),
 ('c0000000-0000-0000-0000-000000000005','Manager','Manages a Dept/BU'),
 ('c0000000-0000-0000-0000-000000000006','Trustee','A trustee of the trust'),
 ('c0000000-0000-0000-0000-000000000006','Manager','Manages a Dept/BU');

INSERT INTO users (user_id, name, personal_email, user_type, is_super_user, expertise_ids) VALUES
 ('11111111-0000-0000-0000-000000000003','Meera Iyer','meera.iyer@example.com','Individual',true,'{e0000000-0000-0000-0000-000000000002,e0000000-0000-0000-0000-000000000004}'),
 ('11111111-0000-0000-0000-000000000002','Vikram Shah','vikram.shah@example.com','Individual',false,'{e0000000-0000-0000-0000-000000000001}'),
 ('11111111-0000-0000-0000-000000000004','Ravi Kumar','ravi.kumar@example.com','Individual',false,'{e0000000-0000-0000-0000-000000000001,e0000000-0000-0000-0000-000000000004}'),
 ('11111111-0000-0000-0000-000000000001','Asha Rao','asha.rao@example.com','Individual',false,'{e0000000-0000-0000-0000-000000000004}'),
 ('11111111-0000-0000-0000-000000000011','Northwind Supplies','accounts@northwind.example.com','Company',false,'{}'),
 ('11111111-0000-0000-0000-000000000012','Ledgerline Traders','finance@ledgerline.example.com','Company',false,'{}'),
 ('11111111-0000-0000-0000-000000000021','Invoice Reader',NULL,'AI',false,'{}');

-- Companies: their Dept/BUs and roles are copied from the company type
INSERT INTO users (user_id, name, personal_email, user_type) VALUES
 ('11111111-0000-0000-0000-000000000013','Orbit IT Services','hello@orbit.example.com','Company');

-- Companies: their Dept/BUs and roles are copied from the company type; each carries its own persona type
INSERT INTO company (user_id, company_type_id, persona_type_id) VALUES
 ('11111111-0000-0000-0000-000000000011','c0000000-0000-0000-0000-000000000003', (SELECT persona_type_id FROM persona_type WHERE slug = 'trading_firm')),
 ('11111111-0000-0000-0000-000000000012','c0000000-0000-0000-0000-000000000002', (SELECT persona_type_id FROM persona_type WHERE slug = 'retail_smb')),
 ('11111111-0000-0000-0000-000000000013','c0000000-0000-0000-0000-000000000003', (SELECT persona_type_id FROM persona_type WHERE slug = 'it_services'));

-- Catalogue domains (platform owned): Compliance / Process / Commercial → Domain → Domain persona (metadata only)
INSERT INTO catalogue_domain (domain_id, catalogue, name) VALUES
 ('d0000000-0000-0000-0000-000000000001', 'Commercial', 'Accounting services'),
 ('d0000000-0000-0000-0000-000000000002', 'Commercial', 'Office and workplace'),
 ('d0000000-0000-0000-0000-000000000003', 'Commercial', 'IT services'),
 ('d0000000-0000-0000-0000-000000000004', 'Process', 'Finance operations'),
 ('d0000000-0000-0000-0000-000000000005', 'Process', 'Procurement'),
 ('d0000000-0000-0000-0000-000000000006', 'Compliance', 'Indirect tax'),
 ('d0000000-0000-0000-0000-000000000007', 'Compliance', 'Company law');
INSERT INTO domain_persona (domain_persona_id, domain_id, name, metadata) VALUES
 ('d1000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'Bookkeeping, monthly', 'Ledger upkeep and reconciliations on a monthly cycle'),
 ('d1000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000002', 'Office supplies', 'Stationery, consumables and small equipment'),
 ('d1000000-0000-0000-0000-000000000003', 'd0000000-0000-0000-0000-000000000003', 'IT support plan', 'Helpdesk and device support on a monthly plan'),
 ('d1000000-0000-0000-0000-000000000004', 'd0000000-0000-0000-0000-000000000004', 'Expense reimbursement', 'Employee claims against receipts'),
 ('d1000000-0000-0000-0000-000000000005', 'd0000000-0000-0000-0000-000000000005', 'Vendor onboarding', 'Setting up a new vendor for purchase'),
 ('d1000000-0000-0000-0000-000000000006', 'd0000000-0000-0000-0000-000000000006', 'GST return, monthly', 'GSTR-1 and GSTR-3B filing each month'),
 ('d1000000-0000-0000-0000-000000000007', 'd0000000-0000-0000-0000-000000000007', 'Annual filing', 'Annual return and financial statements with the registrar');

-- Platform catalogue library (domain form): metadata, seller and buyer persona types
INSERT INTO library_item (library_item_id, kind, name, metadata, domain_persona_id, seller_persona_type_id, buyer_persona_type_id) VALUES
 ('b0000000-0000-0000-0000-000000000001', 'SKU', 'Office supplies', 'Stationery, consumables and small equipment', 'd1000000-0000-0000-0000-000000000002',
  (SELECT persona_type_id FROM persona_type WHERE slug = 'trading'), (SELECT persona_type_id FROM persona_type WHERE slug = 'trading')),
 ('b0000000-0000-0000-0000-000000000002', 'Services', 'IT support', 'Helpdesk and device support on a monthly plan', 'd1000000-0000-0000-0000-000000000003',
  (SELECT persona_type_id FROM persona_type WHERE slug = 'technology_services'), (SELECT persona_type_id FROM persona_type WHERE slug = 'trading')),
 ('b0000000-0000-0000-0000-000000000003', 'Services', 'Monthly bookkeeping', 'Books kept and reconciled every month', 'd1000000-0000-0000-0000-000000000001',
  NULL, NULL);

INSERT INTO person_entity_link (person_id, company_user_id, dept_bu_id, role_id, is_full_time, is_entity_super_user)
SELECT '11111111-0000-0000-0000-000000000002'::uuid, '11111111-0000-0000-0000-000000000012'::uuid,
       (SELECT dept_bu_id FROM dept_bu WHERE company_user_id = '11111111-0000-0000-0000-000000000012' AND name = 'Finance'),
       (SELECT role_id FROM role_definition WHERE company_user_id = '11111111-0000-0000-0000-000000000012' AND name = 'Partner'), true, true
UNION ALL
SELECT '11111111-0000-0000-0000-000000000004'::uuid, '11111111-0000-0000-0000-000000000012'::uuid,
       (SELECT dept_bu_id FROM dept_bu WHERE company_user_id = '11111111-0000-0000-0000-000000000012' AND name = 'Finance'),
       (SELECT role_id FROM role_definition WHERE company_user_id = '11111111-0000-0000-0000-000000000012' AND name = 'Manager'), true, false
UNION ALL
SELECT '11111111-0000-0000-0000-000000000001'::uuid, '11111111-0000-0000-0000-000000000011'::uuid,
       (SELECT dept_bu_id FROM dept_bu WHERE company_user_id = '11111111-0000-0000-0000-000000000011' AND name = 'Sales'),
       (SELECT role_id FROM role_definition WHERE company_user_id = '11111111-0000-0000-0000-000000000011' AND name = 'Executive'), true, true;

-- ---------- platform Kramas ----------
DO $$
DECLARE k uuid; s1 uuid; s2 uuid; t1 uuid; t2 uuid; q1 uuid; q2 uuid; q3 uuid; q4 uuid; ck uuid; cs uuid; ct uuid;
  meera uuid := '11111111-0000-0000-0000-000000000003';
  vikram uuid := '11111111-0000-0000-0000-000000000002';
  ravi uuid := '11111111-0000-0000-0000-000000000004';
  asha uuid := '11111111-0000-0000-0000-000000000001';
  ledger uuid := '11111111-0000-0000-0000-000000000012';
  north uuid := '11111111-0000-0000-0000-000000000011';
  ek uuid; ev2 uuid; item uuid; rid uuid; x uuid;
BEGIN
  INSERT INTO krama (code, name, ownership_type, tag_kind, tag_domain)
  VALUES ('VIA', 'Vendor invoice approval', 'Platform Built Entity Owned', 'Business', 'Process')
  RETURNING krama_id INTO k;
  INSERT INTO room_template (krama_id, kind, label) VALUES (k,'PR','Private room'), (k,'IR','Internal room'), (k,'ER','Vendor room');
  INSERT INTO stage (krama_id, name, seq, path) VALUES (k, 'Receive invoice', 1, 'PR → IR → ER') RETURNING stage_id INTO s1;
  INSERT INTO stage (krama_id, name, seq, path) VALUES (k, 'Approve invoice', 2, 'PR → IR') RETURNING stage_id INTO s2;
  INSERT INTO topic (stage_id, name, seq, path) VALUES (s1, 'Invoice', 1, 'PR → IR → ER') RETURNING topic_id INTO t1;
  INSERT INTO topic (stage_id, name, seq, path) VALUES (s2, 'Purchase order match', 1, 'PR → IR') RETURNING topic_id INTO t2;
  INSERT INTO question (topic_id, text, seq, flow_option, ask_in, rules, due_days) VALUES
   (t1, 'Vendor invoice', 1, 'File drop', 'ER', 'Invoice file with number, date, amount and GST number. Document first: read the file, ask only what it lacks.', 3)
   RETURNING question_id INTO q1;
  INSERT INTO question (topic_id, text, seq, flow_option, ask_in, rules, due_days) VALUES
   (t1, 'Delivery note', 2, 'Input field', 'ER', 'Delivery note number and date for the goods on the invoice.', 3) RETURNING question_id INTO q2;
  INSERT INTO question (topic_id, text, seq, flow_option, ask_in, rules, due_days, setup_columns) VALUES
   (t2, 'Match invoice to purchase order', 1, 'Table grid', 'IR', 'Each invoice line matches a purchase order line on item, quantity and price.', 5,
    E'Invoice line\nPO line\nQuantity\nPrice') RETURNING question_id INTO q3;
  INSERT INTO question (topic_id, text, seq, flow_option, ask_in, rules, due_days) VALUES
   (t2, 'Payment approval', 2, 'Decision', 'IR', 'Approve payment once the match is agreed.', 7) RETURNING question_id INTO q4;
  INSERT INTO question_link (question_id, predecessor_id) VALUES (q2, q1), (q3, q1), (q3, q2), (q4, q3);
  INSERT INTO report (krama_id, name, question_text) VALUES (k, 'Invoices by status', 'How many invoices are open, agreed or dropped, by room?');
  INSERT INTO expertise_required (stage_id, expertise_id, mapped_as) VALUES
   (s1, 'e0000000-0000-0000-0000-000000000004', 'Provider'), (s1, 'e0000000-0000-0000-0000-000000000001', 'Consumer'),
   (s2, 'e0000000-0000-0000-0000-000000000001', 'Provider');
  PERFORM set_krama_status(k, meera, 'Learning and Training');
  PERFORM set_krama_status(k, meera, 'Testing');
  PERFORM set_krama_status(k, meera, 'Published');

  -- Platform Built Platform Owned: used as is
  INSERT INTO krama (code, name, ownership_type, tag_kind, tag_domain)
  VALUES ('CONNECT', 'Connect entity', 'Platform Built Platform Owned', 'Business', 'Network') RETURNING krama_id INTO ck;
  INSERT INTO room_template (krama_id, kind, label) VALUES (ck, 'PR', 'Private room');
  INSERT INTO stage (krama_id, name, seq, path) VALUES (ck, 'Connect', 1, 'PR only') RETURNING stage_id INTO cs;
  INSERT INTO topic (stage_id, name, seq, path) VALUES (cs, 'Entity details', 1, 'PR only') RETURNING topic_id INTO ct;
  INSERT INTO question (topic_id, text, flow_option, ask_in, rules) VALUES (ct, 'Confirm entity details', 'Input field', 'PR', 'Legal name and registration number of the entity to connect.');
  INSERT INTO report (krama_id, name, question_text) VALUES (ck, 'Connections made', 'How many entities were connected this FY?');
  PERFORM set_krama_status(ck, meera, 'Published');

  -- Ledgerline imports the platform Krama, customises it and publishes it
  ek := import_krama(k, ledger, vikram);
  INSERT INTO question (topic_id, text, seq, flow_option, ask_in, rules, due_days)
  SELECT t.topic_id, 'Bank details confirmed', 3, 'Decision', 'IR', 'Vendor bank details match the master before payment.', 5
    FROM topic t JOIN stage s USING (stage_id) WHERE s.krama_id = ek AND t.name = 'Purchase order match';
  PERFORM set_krama_status(ek, vikram, 'Testing');
  PERFORM set_krama_status(ek, vikram, 'Published');
  item := add_catalogue_item(ek, ledger, vikram, 'Office supplies');
  UPDATE catalogue_item SET library_item_id = 'b0000000-0000-0000-0000-000000000001', library_use = 'Customised', item_type = 'SKU',
         catalogue = 'Commercial', domain_persona_id = 'd1000000-0000-0000-0000-000000000002', release = 'Beta', review = 'Success',
         visibility_scope = 'External', visibility_audience = 'Vendor', visibility_reach = 'Customised', visibility_names = ARRAY[north]
   WHERE item_id = item;
  UPDATE catalogue_variant SET name = 'Monthly order', pricing_type = 'Per unit', hsn_sac = '4820', gst_rate = 18 WHERE item_id = item;
  INSERT INTO catalogue_variant (item_id, name, seq, pricing_type, hsn_sac, gst_rate) VALUES (item, 'Quarterly order', 2, 'Request quote', '4820', 18);
  PERFORM add_catalogue_item((SELECT krama_id FROM krama WHERE code = 'CONNECT'), ledger, vikram, 'Connect entity');

  -- Catalogue items as the Catalogue screens show them (Owned for Ledgerline; Northwind's shared item is Borrowed)
  INSERT INTO catalogue_item (company_user_id, name, item_type, catalogue, domain_persona_id, library_item_id, library_use, release, review,
                              visibility_scope, visibility_audience, visibility_reach, visibility_names, content_title, brand_name, category, sub_category, competitors)
  VALUES (north, 'Office supplies', 'SKU', 'Commercial', 'd1000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-000000000001', 'As it is',
          'General Availability', 'Success', 'External', 'Client', 'Customised', ARRAY[ledger], 'Office supplies', 'Northwind Office', 'Supplies', 'Stationery', '[]')
  RETURNING item_id INTO x;
  INSERT INTO catalogue_variant (item_id, name, pricing_type, price, hsn_sac, gst_rate, promo) VALUES (x, 'Standard pack', 'Per unit', 450, '4820', 18, 'Not applicable');
  INSERT INTO catalogue_seat (item_id, seat, side, dept_bu_id) VALUES
   (x, 'Seller', 'Internal', (SELECT dept_bu_id FROM dept_bu WHERE company_user_id = north AND name = 'Sales')),
   (x, 'Fulfiller', 'Internal', (SELECT dept_bu_id FROM dept_bu WHERE company_user_id = north AND name = 'Operations'));

  SELECT item_id INTO item FROM catalogue_item WHERE company_user_id = ledger AND name = 'Office supplies';
  INSERT INTO catalogue_seat (item_id, seat, side, dept_bu_id, party_id, vendor_item_id) VALUES
   (item, 'Buyer', 'Internal', (SELECT dept_bu_id FROM dept_bu WHERE company_user_id = ledger AND name = 'Operations'), NULL, NULL),
   (item, 'Fulfiller', 'External', NULL, north, x),
   (item, 'Assurer', 'Internal', (SELECT dept_bu_id FROM dept_bu WHERE company_user_id = ledger AND name = 'Finance'), NULL, NULL);

  item := create_catalogue_item(ledger, vikram, '{"catalogue": "Commercial", "library_item_id": "b0000000-0000-0000-0000-000000000003", "library_use": "Customised"}');
  UPDATE catalogue_item SET release = 'General Availability', review = 'Success', visibility_scope = 'External', visibility_audience = 'Client',
         visibility_reach = 'Generic', brand_name = 'Ledgerline Books', category = 'Accounting', sub_category = 'Bookkeeping',
         main_image = 'bookkeeping.jpg', content_blocks = '[{"kind": "Text", "body": "Your books kept, reconciled and closed every month, with a short report on the 5th."}]',
         competitors = '[{"brand": "BookKeep", "business": "BookKeep Services LLP", "website": "https://bookkeep.example"}]'
   WHERE item_id = item;
  UPDATE catalogue_variant SET name = 'Starter', pricing_type = 'Fixed', price = 4500, hsn_sac = '998222', gst_rate = 18,
         quotation_wording = 'Monthly bookkeeping, up to 100 entries', invoice_wording = 'Bookkeeping fee for the month',
         offer_kind = '%', offer_amount = 10, offer_until = current_date + 30, promo = '10% off the first three months' WHERE item_id = item;
  INSERT INTO catalogue_variant (item_id, name, seq, pricing_type, price, hsn_sac, gst_rate, promo) VALUES
   (item, 'Growth', 2, 'Fixed', 9000, '998222', 18, 'Not applicable'),
   (item, 'Custom', 3, 'Request quote', NULL, '998222', 18, 'Not applicable');
  INSERT INTO catalogue_seat (item_id, seat, side, dept_bu_id) VALUES
   (item, 'Seller', 'Internal', (SELECT dept_bu_id FROM dept_bu WHERE company_user_id = ledger AND name = 'Finance')),
   (item, 'Fulfiller', 'Internal', (SELECT dept_bu_id FROM dept_bu WHERE company_user_id = ledger AND name = 'Finance')),
   (item, 'Assurer', 'Internal', (SELECT dept_bu_id FROM dept_bu WHERE company_user_id = ledger AND name = 'Operations'));

  item := create_catalogue_item(ledger, vikram, '{"catalogue": "Compliance", "domain_persona_id": "d1000000-0000-0000-0000-000000000006", "name": "GST monthly return"}');
  UPDATE catalogue_item SET release = 'Pilot', visibility_scope = 'Internal', visibility_audience = 'Self',
         host_dept_bu_id = (SELECT dept_bu_id FROM dept_bu WHERE company_user_id = ledger AND name = 'Finance')
   WHERE item_id = item;
  SELECT item_id INTO item FROM catalogue_item WHERE company_user_id = ledger AND name = 'Office supplies';

  -- The platform later publishes v2, so Ledgerline sees "Newer version available"
  ev2 := new_version(k, meera, 'Added a due-date check to the invoice question');
  UPDATE question SET rules = rules || ' Flag invoices due within 7 days.'
   WHERE text = 'Vendor invoice' AND topic_id IN (SELECT topic_id FROM topic JOIN stage USING (stage_id) WHERE krama_id = ev2);
  PERFORM set_krama_status(ev2, meera, 'Testing');
  PERFORM set_krama_status(ev2, meera, 'Published');

  -- Relationship matrix: Vendor invoice approval applies to vendors whose persona type is Trading (or narrower)
  INSERT INTO krama_relationship (krama_id, relationship, party_type, persona_type_id)
  SELECT kk, rel, 'Entity', (SELECT persona_type_id FROM persona_type WHERE slug = 'trading')
    FROM unnest(ARRAY[k, ev2]) kk, unnest(ARRAY['Pre-vendor','Vendor']) rel;

  -- Service acceptance (Platform Built Platform Owned): applies to vendors whose persona type is Services (or narrower)
  INSERT INTO krama (code, name, ownership_type, tag_kind, tag_domain)
  VALUES ('SAC', 'Service acceptance', 'Platform Built Platform Owned', 'Business', 'Process') RETURNING krama_id INTO ck;
  INSERT INTO room_template (krama_id, kind, label) VALUES (ck, 'PR', 'Private room'), (ck, 'ER', 'Vendor room');
  INSERT INTO stage (krama_id, name, seq, path) VALUES (ck, 'Accept service', 1, 'PR → IR → ER') RETURNING stage_id INTO cs;
  INSERT INTO topic (stage_id, name, seq, path) VALUES (cs, 'Service', 1, 'PR → IR → ER') RETURNING topic_id INTO ct;
  INSERT INTO question (topic_id, text, flow_option, ask_in, rules) VALUES
   (ct, 'Service delivered as agreed', 'Decision', 'ER', 'Confirm the service for the period was delivered to the agreed levels.');
  INSERT INTO report (krama_id, name, question_text) VALUES (ck, 'Services accepted', 'How many service periods were accepted or disputed?');
  PERFORM set_krama_status(ck, meera, 'Published');
  INSERT INTO krama_relationship (krama_id, relationship, party_type, persona_type_id)
  VALUES (ck, 'Vendor', 'Entity', (SELECT persona_type_id FROM persona_type WHERE slug = 'services'));
  -- Ledgerline's Office supplies: two vendors of different persona types get different Kramas
  PERFORM assign_krama(item, ck, vikram);

  -- A run with Northwind as the vendor
  rid := activate(item, vikram, north, 'Vendor', NULL);
  PERFORM seat_person(rid, (SELECT stage_id FROM stage WHERE krama_id = ek AND name = 'Receive invoice'), 'Doer', asha, vikram);
  PERFORM seat_person(rid, (SELECT stage_id FROM stage WHERE krama_id = ek AND name = 'Receive invoice'), 'Approver', ravi, vikram);
  PERFORM seat_person(rid, (SELECT stage_id FROM stage WHERE krama_id = ek AND name = 'Receive invoice'), 'SPOC', asha, vikram);
  PERFORM seat_person(rid, (SELECT stage_id FROM stage WHERE krama_id = ek AND name = 'Approve invoice'), 'Doer', ravi, vikram);
  PERFORM seat_person(rid, (SELECT stage_id FROM stage WHERE krama_id = ek AND name = 'Approve invoice'), 'Approver', vikram, vikram);

  SELECT qr_id INTO x FROM question_run JOIN question USING (question_id) WHERE run_id = rid AND text = 'Vendor invoice';
  PERFORM submit_answer(x, asha, 'INV-1042 dated 28 Oct 2026, 1,20,000, GST number 29ABCDE1234F1Z5', 'OCR');
  PERFORM agree_answer(x, ravi);
  SELECT qr_id INTO x FROM question_run JOIN question USING (question_id) WHERE run_id = rid AND text = 'Delivery note';
  PERFORM submit_answer(x, asha, 'DN-55', 'Person');
  PERFORM contest_answer(x, ravi, 'Evidence missing', 'Please give the delivery note date and attach the signed copy.');
END $$;

-- A Standalone task of Vikram's
INSERT INTO standalone_task (owner_id, company_user_id, title, notes, due_date, quadrant) VALUES
 ('11111111-0000-0000-0000-000000000002', '11111111-0000-0000-0000-000000000012',
  'Review vendor payment terms', 'Check the credit days we offer our top vendors', current_date + 4, 'Do now');

-- ======================= One example of every scenario =======================

-- A second Ledgerline person (Reviewer examples); Ravi also works part-time for Northwind, with Ledgerline's approval
INSERT INTO users (user_id, name, personal_email, user_type, expertise_ids) VALUES
 ('11111111-0000-0000-0000-000000000005','Priya Nair','priya.nair@example.com','Individual','{e0000000-0000-0000-0000-000000000004}');
INSERT INTO person_entity_link (person_id, company_user_id, dept_bu_id, role_id, is_full_time)
SELECT '11111111-0000-0000-0000-000000000005'::uuid, '11111111-0000-0000-0000-000000000012'::uuid,
       (SELECT dept_bu_id FROM dept_bu WHERE company_user_id = '11111111-0000-0000-0000-000000000012' AND name = 'Finance'),
       (SELECT role_id FROM role_definition WHERE company_user_id = '11111111-0000-0000-0000-000000000012' AND name = 'Executive'), true;
INSERT INTO person_entity_link (person_id, company_user_id, dept_bu_id, is_full_time, employer_approved)
SELECT '11111111-0000-0000-0000-000000000004'::uuid, '11111111-0000-0000-0000-000000000011'::uuid,
       (SELECT dept_bu_id FROM dept_bu WHERE company_user_id = '11111111-0000-0000-0000-000000000011' AND name = 'Finance'), false, true;

DO $$
DECLARE
  meera uuid := '11111111-0000-0000-0000-000000000003';
  vikram uuid := '11111111-0000-0000-0000-000000000002';
  ravi uuid := '11111111-0000-0000-0000-000000000004';
  asha uuid := '11111111-0000-0000-0000-000000000001';
  priya uuid := '11111111-0000-0000-0000-000000000005';
  ledger uuid := '11111111-0000-0000-0000-000000000012';
  north uuid := '11111111-0000-0000-0000-000000000011';
  k uuid; s1 uuid; s2 uuid; t1 uuid; t2 uuid; q1 uuid; q2 uuid; q3 uuid; item uuid; r uuid; x uuid; v2 uuid; ck uuid;
BEGIN
  -- Entity Built Entity Owned: Ledgerline's internal Expense claim (PR → IR), Published
  INSERT INTO krama (code, name, owner_entity, ownership_type, pool_mark, tag_kind, tag_domain)
  VALUES ('EXP', 'Expense claim', ledger, 'Entity Built Entity Owned', 'Entity Built', 'Business', 'Process')
  RETURNING krama_id INTO k;
  INSERT INTO room_template (krama_id, kind, label) VALUES (k,'PR','Private room'), (k,'IR','Finance room');
  INSERT INTO stage (krama_id, name, seq, path) VALUES (k, 'Submit claim', 1, 'PR → IR') RETURNING stage_id INTO s1;
  INSERT INTO stage (krama_id, name, seq, path) VALUES (k, 'Approve claim', 2, 'PR → IR') RETURNING stage_id INTO s2;
  INSERT INTO topic (stage_id, name, seq, path) VALUES (s1, 'Claim', 1, 'PR → IR') RETURNING topic_id INTO t1;
  INSERT INTO topic (stage_id, name, seq, path) VALUES (s2, 'Approval', 1, 'PR → IR') RETURNING topic_id INTO t2;
  INSERT INTO question (topic_id, text, seq, flow_option, ask_in, rules, due_days) VALUES
   (t1, 'Claim details', 1, 'Input field', 'IR', 'Purpose, date and amount of the expense.', 2) RETURNING question_id INTO q1;
  INSERT INTO question (topic_id, text, seq, flow_option, ask_in, rules, due_days) VALUES
   (t1, 'Receipts', 2, 'File drop', 'IR', 'A receipt for every line of the claim.', 3) RETURNING question_id INTO q2;
  INSERT INTO question (topic_id, text, seq, flow_option, ask_in, rules, due_days) VALUES
   (t2, 'Approve reimbursement', 1, 'Decision', 'IR', 'Approve once details and receipts are agreed.', 5) RETURNING question_id INTO q3;
  INSERT INTO question_link (question_id, predecessor_id) VALUES (q2, q1), (q3, q2);
  INSERT INTO report (krama_id, name, question_text) VALUES (k, 'Claims by month', 'How many claims were fulfilled or unfulfilled each month?');
  PERFORM set_krama_status(k, vikram, 'Published');
  item := add_catalogue_item(k, ledger, vikram, 'Expense claim');
  UPDATE catalogue_item SET item_type = 'SDU', domain_persona_id = 'd1000000-0000-0000-0000-000000000004', release = 'General Availability',
         review = 'Success', visibility_scope = 'Internal', visibility_audience = 'Internal client', visibility_reach = 'Generic',
         host_dept_bu_id = (SELECT dept_bu_id FROM dept_bu WHERE company_user_id = ledger AND name = 'Finance')
   WHERE item_id = item;
  UPDATE catalogue_variant SET name = 'Per claim', pricing_type = 'Per unit', price = 0, tax_mode = 'tax included' WHERE item_id = item;
  INSERT INTO catalogue_journey_step (variant_id, step, krama_id) SELECT variant_id, 'Process', k FROM catalogue_variant WHERE item_id = item;

  -- Run: Fulfilled and conserved
  r := activate(item, ravi, NULL, 'Department', NULL);
  PERFORM seat_person(r, s1, 'Doer', ravi, ravi);     PERFORM seat_person(r, s1, 'Approver', vikram, ravi);
  PERFORM seat_person(r, s2, 'Doer', ravi, ravi);     PERFORM seat_person(r, s2, 'Approver', vikram, ravi);
  SELECT qr_id INTO x FROM question_run WHERE run_id = r AND question_id = q1;
  PERFORM submit_answer(x, ravi, 'Client visit, 21 Oct, 4,800', 'Person'); PERFORM agree_answer(x, vikram);
  SELECT qr_id INTO x FROM question_run WHERE run_id = r AND question_id = q2;
  PERFORM submit_answer(x, ravi, 'Taxi and lunch receipts', 'OCR'); PERFORM agree_answer(x, vikram);
  SELECT qr_id INTO x FROM question_run WHERE run_id = r AND question_id = q3;
  PERFORM submit_answer(x, ravi, 'Reimburse 4,800', 'Person'); PERFORM agree_answer(x, vikram);

  -- Run: contested, then deadlocked (Dropped), the rest cancelled → Unfulfilled and conserved
  r := activate(item, ravi, NULL, 'Department', NULL);
  PERFORM seat_person(r, s1, 'Doer', ravi, ravi);     PERFORM seat_person(r, s1, 'Approver', vikram, ravi);
  PERFORM seat_person(r, s2, 'Doer', ravi, ravi);     PERFORM seat_person(r, s2, 'Approver', vikram, ravi);
  SELECT qr_id INTO x FROM question_run WHERE run_id = r AND question_id = q1;
  PERFORM submit_answer(x, ravi, 'Team dinner, 18 Oct, 22,000', 'Person');
  PERFORM contest_answer(x, vikram, 'Disagree', 'Team dinners are not reimbursable under our policy.');
  PERFORM submit_answer(x, ravi, 'Team dinner with a client present, 18 Oct, 22,000', 'Person');
  PERFORM deadlock_answer(x, vikram, 'Ravi: a client was present. Vikram: the policy still excludes team dinners.');
  SELECT qr_id INTO x FROM question_run WHERE run_id = r AND question_id = q2;
  PERFORM cancel_question(x, ravi, 'Claim details were deadlocked, so receipts are no longer needed.');
  SELECT qr_id INTO x FROM question_run WHERE run_id = r AND question_id = q3;
  PERFORM cancel_question(x, ravi, 'Nothing left to approve.');

  -- Run: fulfilled, then amended (A1) with a reopened question
  r := activate(item, ravi, NULL, 'Department', NULL);
  PERFORM seat_person(r, s1, 'Doer', ravi, ravi);     PERFORM seat_person(r, s1, 'Approver', vikram, ravi);
  PERFORM seat_person(r, s2, 'Doer', ravi, ravi);     PERFORM seat_person(r, s2, 'Approver', vikram, ravi);
  SELECT qr_id INTO x FROM question_run WHERE run_id = r AND question_id = q1;
  PERFORM submit_answer(x, ravi, 'Vendor meeting travel, 24 Oct, 3,200', 'Person'); PERFORM agree_answer(x, vikram);
  SELECT qr_id INTO x FROM question_run WHERE run_id = r AND question_id = q2;
  PERFORM submit_answer(x, ravi, 'Train ticket', 'OCR'); PERFORM agree_answer(x, vikram);
  SELECT qr_id INTO x FROM question_run WHERE run_id = r AND question_id = q3;
  PERFORM submit_answer(x, ravi, 'Reimburse 3,200', 'Person'); PERFORM agree_answer(x, vikram);
  PERFORM amend_run(r, ravi);
  PERFORM reopen_question(x, ravi);

  -- Run: maker-checker — answer waiting for the Reviewer
  r := activate(item, ravi, NULL, 'Department', NULL);
  PERFORM seat_person(r, s1, 'Doer', ravi, ravi);     PERFORM seat_person(r, s1, 'Reviewer', priya, ravi);
  PERFORM seat_person(r, s1, 'Approver', vikram, ravi);
  PERFORM seat_person(r, s2, 'Doer', ravi, ravi);     PERFORM seat_person(r, s2, 'Approver', vikram, ravi);
  SELECT qr_id INTO x FROM question_run WHERE run_id = r AND question_id = q1;
  PERFORM submit_answer(x, ravi, 'Conference fee, 27 Oct, 12,500', 'Person');

  -- Vendor invoice run with Northwind: reviewed, now waiting for the Approver
  SELECT item_id INTO item FROM catalogue_item WHERE company_user_id = ledger AND name = 'Office supplies';
  SELECT krama_id INTO k FROM krama WHERE owner_entity = ledger AND code = 'VIA';
  r := activate(item, vikram, north, 'Vendor', NULL);
  SELECT stage_id INTO s1 FROM stage WHERE krama_id = k AND name = 'Receive invoice';
  SELECT stage_id INTO s2 FROM stage WHERE krama_id = k AND name = 'Approve invoice';
  PERFORM seat_person(r, s1, 'Doer', asha, vikram);   PERFORM seat_person(r, s1, 'Reviewer', priya, vikram);
  PERFORM seat_person(r, s1, 'Approver', ravi, vikram);
  PERFORM seat_person(r, s2, 'Doer', ravi, vikram);   PERFORM seat_person(r, s2, 'Approver', vikram, vikram);
  SELECT x2.qr_id INTO x FROM question_run x2 JOIN question q USING (question_id) WHERE x2.run_id = r AND q.text = 'Vendor invoice';
  PERFORM submit_answer(x, asha, 'INV-1077 dated 29 Oct 2026, 64,000, GST number 29ABCDE1234F1Z5', 'OCR');
  PERFORM review_answer(x, priya);

  -- Platform Built Platform Owned (Connect entity), used as is: a fulfilled run
  SELECT item_id INTO item FROM catalogue_item WHERE company_user_id = ledger AND name = 'Connect entity';
  SELECT krama_id INTO ck FROM krama WHERE code = 'CONNECT';
  r := activate(item, vikram, NULL, 'Department', NULL);
  PERFORM seat_person(r, (SELECT stage_id FROM stage WHERE krama_id = ck), 'Doer', ravi, vikram);
  PERFORM seat_person(r, (SELECT stage_id FROM stage WHERE krama_id = ck), 'Approver', vikram, vikram);
  SELECT qr_id INTO x FROM question_run WHERE run_id = r;
  PERFORM submit_answer(x, ravi, 'Northwind Supplies Pvt Ltd, U12345KA2019PTC000001', 'Platform data');
  PERFORM agree_answer(x, vikram);

  -- Northwind imports the platform v2 and publishes it unchanged (pool mark stays Platform built)
  SELECT krama_id INTO v2 FROM krama WHERE owner_entity IS NULL AND code = 'VIA' AND version = 2;
  k := import_krama(v2, north, asha);
  PERFORM set_krama_status(k, asha, 'Published');

  -- Kramas at each earlier lifecycle status
  INSERT INTO krama (code, name, owner_entity, ownership_type, pool_mark, tag_kind, tag_domain)
  VALUES ('POA', 'Purchase order approval', north, 'Entity Built Entity Owned', 'Entity Built', 'Business', 'Process')
  RETURNING krama_id INTO k;
  INSERT INTO room_template (krama_id, kind, label) VALUES (k,'PR','Private room'), (k,'ER','Client room');
  INSERT INTO stage (krama_id, name, seq, path) VALUES (k, 'Receive order', 1, 'PR → IR → ER') RETURNING stage_id INTO s1;
  INSERT INTO topic (stage_id, name, seq, path) VALUES (s1, 'Order', 1, 'PR → IR → ER') RETURNING topic_id INTO t1;
  INSERT INTO question (topic_id, text, flow_option, ask_in, rules) VALUES (t1, 'Purchase order', 'File drop', 'ER', 'Signed purchase order from the client.');
  INSERT INTO report (krama_id, name, question_text) VALUES (k, 'Orders received', 'How many orders were received this month?');
  PERFORM set_krama_status(k, asha, 'Testing');      -- Testing (Beta)

  INSERT INTO krama (code, name, owner_entity, ownership_type, pool_mark, tag_kind, tag_domain)
  VALUES ('PAY', 'Payment run', ledger, 'Entity Built Entity Owned', 'Entity Built', 'Business', 'Process');  -- Created

  INSERT INTO krama (code, name, ownership_type, tag_kind, tag_domain)
  VALUES ('VSU', 'Vendor set-up', 'Platform Built Entity Owned', 'Business', 'Process') RETURNING krama_id INTO k;
  INSERT INTO room_template (krama_id, kind, label) VALUES (k,'PR','Private room');
  PERFORM set_krama_status(k, meera, 'Learning and Training');

  -- Standalone tasks across the quadrants, open and done
  INSERT INTO standalone_task (owner_id, company_user_id, title, notes, due_date, quadrant) VALUES
   (vikram, ledger, 'Renew office lease', 'Landlord wants an answer this week', current_date + 2, 'Do now'),
   (vikram, ledger, 'Collect team leave plan', NULL, current_date + 12, 'Delegate'),
   (vikram, ledger, 'Old courier vendor follow-up', 'Probably not needed', current_date + 20, 'Delete'),
   (asha, north, 'Update price list for Q3 clients', NULL, current_date + 6, 'Do later'),
   (ravi, ledger, 'Close October petty cash', NULL, current_date - 1, 'Do now');
  PERFORM mark_done((SELECT task_id FROM standalone_task WHERE title = 'Close October petty cash'), ravi);
END $$;

-- Priorities (quadrant) on some questions
UPDATE question_run x SET quadrant = 'Do now' FROM question q
 WHERE q.question_id = x.question_id AND q.text IN ('Delivery note','Vendor invoice') AND x.status = 'Open';
UPDATE question_run x SET quadrant = 'Delegate' FROM question q
 WHERE q.question_id = x.question_id AND q.text = 'Approve reimbursement' AND x.status = 'Open';
UPDATE question_run x SET quadrant = 'Delete' FROM question q
 WHERE q.question_id = x.question_id AND q.text = 'Bank details confirmed' AND x.status = 'Open';

-- Yousr (personal) tasks for Vikram: personal items, and one identifier request from an entity
INSERT INTO personal_task (owner_id, kind, requested_by, title, purpose, due_date, quadrant, status, done_at) VALUES
 ('11111111-0000-0000-0000-000000000002', 'Personal', NULL, 'Upload your PAN document', NULL, current_date, 'Do now', 'To do', NULL),
 ('11111111-0000-0000-0000-000000000002', 'Personal', NULL, 'Renew passport', NULL, current_date + 5, 'Do later', 'To do', NULL),
 ('11111111-0000-0000-0000-000000000002', 'Identifier request', '11111111-0000-0000-0000-000000000011', 'Passport requested', 'For director KYC', current_date + 3, 'Do now', 'To do', NULL),
 ('11111111-0000-0000-0000-000000000002', 'Personal', NULL, 'Update home address on ID', NULL, current_date - 2, 'Do later', 'Done', clock_timestamp());

-- Flow-option setups on the seeded questions (all Kramas, so every copy and version matches)
SELECT set_config('demo.seeding', 'on', false);
UPDATE question SET also_needs = 'File drop' WHERE text IN ('Delivery note','Payment approval','Claim details');
UPDATE question SET flow_option = 'Table grid', setup_columns = E'Invoice line\nPO line\nQuantity\nPrice' WHERE text = 'Match invoice to purchase order';
UPDATE question SET flow_option = 'Checklist', setup_options = E'Account name matches\nIFSC code matches\nCancelled cheque received', setup_choices = E'Yes\nNo\nNot applicable'
 WHERE text = 'Bank details confirmed';
-- Phase 3 seed: an output document topic, and capabilities on the Vendor invoice approval Kramas
UPDATE topic SET is_output = true WHERE name = 'Purchase order match';
INSERT INTO capability_use (krama_id, code, topic_id)
SELECT s.krama_id, 'maker_checker', t.topic_id FROM topic t JOIN stage s USING (stage_id) JOIN krama k ON k.krama_id = s.krama_id
 WHERE t.name = 'Purchase order match' AND k.code = 'VIA';
INSERT INTO capability_use (krama_id, code, question_id)
SELECT s.krama_id, 'request_wait', q.question_id FROM question q JOIN topic t USING (topic_id) JOIN stage s USING (stage_id) JOIN krama k ON k.krama_id = s.krama_id
 WHERE q.text = 'Delivery note' AND k.code = 'VIA';
SELECT set_config('demo.seeding', 'off', false);
