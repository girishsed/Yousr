-- =====================================================================================
-- More sample entities and people across domains (business examples only).
-- Six more entities across Trading, Services, Manufacturing and Other; eight more people;
-- six more domains with domain personas and profiles; catalogue items; connections.
-- =====================================================================================

-- ---------- domains, domain personas and their profiles ----------
INSERT INTO catalogue_domain (domain_id, catalogue, name) VALUES
 ('d0000000-0000-0000-0000-000000000011', 'Commercial', 'Logistics services'),
 ('d0000000-0000-0000-0000-000000000012', 'Commercial', 'Raw materials'),
 ('d0000000-0000-0000-0000-000000000013', 'Process', 'Payroll'),
 ('d0000000-0000-0000-0000-000000000014', 'Process', 'Quality control'),
 ('d0000000-0000-0000-0000-000000000015', 'Compliance', 'Income tax'),
 ('d0000000-0000-0000-0000-000000000016', 'Compliance', 'Labour law');
INSERT INTO domain_persona (domain_persona_id, domain_id, name, metadata, obligatory, requirements, permissible, not_permissible, seats) VALUES
 ('d1000000-0000-0000-0000-000000000011', 'd0000000-0000-0000-0000-000000000011', 'Freight forwarding, domestic', 'Pickup, line haul and delivery within India', false,
  'Goods move against a booking with a delivery note signed at the destination.', '{Part load,Full truck load}', '{Movement without e-way bill}', '{Fulfiller}'),
 ('d1000000-0000-0000-0000-000000000012', 'd0000000-0000-0000-0000-000000000012', 'Yarn and fabric supply', 'Bulk supply against purchase orders', false,
  'Supply matches the purchase order and the test certificate.', '{Scheduled deliveries}', '{Supply without a test certificate}', '{Fulfiller,Auditor}'),
 ('d1000000-0000-0000-0000-000000000013', 'd0000000-0000-0000-0000-000000000013', 'Monthly payroll run', 'Salaries computed and paid each month', false,
  'Attendance closed, salaries computed, approved and paid by the due date.', '{Bank transfer}', '{Cash salary above limits}', '{Fulfiller,Auditor}'),
 ('d1000000-0000-0000-0000-000000000014', 'd0000000-0000-0000-0000-000000000014', 'Incoming material inspection', 'Checks on material received from vendors', false,
  'Each lot is sampled and accepted or rejected against the specification.', '{Sampling by lot}', '{Accepting a lot without inspection}', '{Fulfiller,Auditor}'),
 ('d1000000-0000-0000-0000-000000000015', 'd0000000-0000-0000-0000-000000000015', 'TDS return, quarterly', 'Quarterly statement of tax deducted at source', true,
  'Deductions reconciled and the quarterly statement filed by its due date.', '{Correction statements}', '{Late filing without fee}', '{Fulfiller,Auditor,Representation}'),
 ('d1000000-0000-0000-0000-000000000016', 'd0000000-0000-0000-0000-000000000016', 'PF and ESI contributions, monthly', 'Employer and employee contributions each month', true,
  'Contributions computed on wages and paid with the monthly return.', '{Online challan}', '{Paying after the due date without interest}', '{Fulfiller,Representation}');
INSERT INTO domain_profile (domain_id, objectives, terminology, regulations, typical_workflows, controls, compliance_requirements) VALUES
 ('d0000000-0000-0000-0000-000000000011', 'Move goods on time, with proof of delivery.', '{Consignment note,E-way bill,Proof of delivery}', '{E-way bill rules}', '{Booking,Pickup,Delivery}', '{Signed delivery note}', NULL),
 ('d0000000-0000-0000-0000-000000000013', 'Pay people correctly and on time.', '{Gross pay,Deductions,Net pay}', '{Payment of Wages Act}', '{Attendance close,Computation,Approval,Payment}', '{Maker-checker on the payroll sheet}', NULL),
 ('d0000000-0000-0000-0000-000000000015', 'Deduct, deposit and report tax at source correctly.', '{TDS,Challan,Form 16A}', '{Income-tax Act}', '{Deduct,Deposit,Report}', '{Reconcile deductions to challans}', 'Quarterly statements by their due dates'),
 ('d0000000-0000-0000-0000-000000000016', 'Pay statutory contributions for every eligible employee.', '{PF,ESI,UAN}', '{EPF Act,ESI Act}', '{Compute,Pay,Return}', '{Headcount match to payroll}', 'Monthly payment and return'),
 ('d0000000-0000-0000-0000-000000000006', 'File indirect tax returns accurately and on time.', '{GSTR-1,GSTR-3B,Input tax credit}', '{CGST Act}', '{Sales register,Purchase register,Return}', '{Reconcile ITC with GSTR-2B}', 'Monthly returns by their due dates');

-- ---------- people ----------
INSERT INTO users (user_id, name, personal_email, user_type, expertise_ids) VALUES
 ('11111111-0000-0000-0000-000000000031', 'Anil Mehta',     'anil.mehta@example.com',     'Individual', '{e0000000-0000-0000-0000-000000000001}'),
 ('11111111-0000-0000-0000-000000000032', 'Fatima Shaikh',  'fatima.shaikh@example.com',  'Individual', '{e0000000-0000-0000-0000-000000000004}'),
 ('11111111-0000-0000-0000-000000000033', 'Karthik Rao',    'karthik.rao@example.com',    'Individual', '{}'),
 ('11111111-0000-0000-0000-000000000034', 'Leena D''Souza', 'leena.dsouza@example.com',   'Individual', '{e0000000-0000-0000-0000-000000000003}'),
 ('11111111-0000-0000-0000-000000000035', 'Suresh Pillai',  'suresh.pillai@example.com',  'Individual', '{e0000000-0000-0000-0000-000000000002}'),
 ('11111111-0000-0000-0000-000000000036', 'Divya Menon',    'divya.menon@example.com',    'Individual', '{e0000000-0000-0000-0000-000000000004}'),
 ('11111111-0000-0000-0000-000000000037', 'Rahul Verma',    'rahul.verma@example.com',    'Individual', '{e0000000-0000-0000-0000-000000000001}'),
 ('11111111-0000-0000-0000-000000000038', 'Sneha Kulkarni', 'sneha.kulkarni@example.com', 'Individual', '{}');

-- ---------- entities ----------
INSERT INTO users (user_id, name, personal_email, user_type) VALUES
 ('11111111-0000-0000-0000-000000000041', 'Brightline Retail',  'accounts@brightline.example.com', 'Company'),
 ('11111111-0000-0000-0000-000000000042', 'Nova Logistics',     'ops@novalogistics.example.com',   'Company'),
 ('11111111-0000-0000-0000-000000000043', 'Kaveri Textiles',    'office@kaveri.example.com',       'Company'),
 ('11111111-0000-0000-0000-000000000044', 'Sterling & Co',      'desk@sterling.example.com',       'Company'),
 ('11111111-0000-0000-0000-000000000045', 'Greenfield Foods',   'finance@greenfield.example.com',  'Company'),
 ('11111111-0000-0000-0000-000000000046', 'Udaya Foundation',   'contact@udaya.example.com',       'Company');
INSERT INTO company (user_id, company_type_id, persona_type_id) VALUES
 ('11111111-0000-0000-0000-000000000041', 'c0000000-0000-0000-0000-000000000003', (SELECT persona_type_id FROM persona_type WHERE slug = 'retail_smb')),
 ('11111111-0000-0000-0000-000000000042', 'c0000000-0000-0000-0000-000000000004', (SELECT persona_type_id FROM persona_type WHERE slug = 'business_operations_services')),
 ('11111111-0000-0000-0000-000000000043', 'c0000000-0000-0000-0000-000000000003', (SELECT persona_type_id FROM persona_type WHERE slug = 'manufacturing_smb')),
 ('11111111-0000-0000-0000-000000000044', 'c0000000-0000-0000-0000-000000000002', (SELECT persona_type_id FROM persona_type WHERE slug = 'ca_practice')),
 ('11111111-0000-0000-0000-000000000045', 'c0000000-0000-0000-0000-000000000005', (SELECT persona_type_id FROM persona_type WHERE slug = 'process_manufacturing')),
 ('11111111-0000-0000-0000-000000000046', 'c0000000-0000-0000-0000-000000000006', (SELECT persona_type_id FROM persona_type WHERE slug = 'non_profit'));
UPDATE company SET category = v.cat, sub_category = v.sub, size = v.size, business_model = v.model, work_email = v.mail,
       objectives = v.obj, capabilities = v.caps
  FROM (VALUES
   ('11111111-0000-0000-0000-000000000041'::uuid, 'Trading', 'Retail', 'Small', 'Business Unit', 'admin@brightline.example.com', 'Grow store sales across the city.', '{Store operations,Buying}'::text[]),
   ('11111111-0000-0000-0000-000000000042'::uuid, 'Services', 'Others', 'Small', 'Functional', 'admin@novalogistics.example.com', 'On-time freight for regional manufacturers.', '{Line haul,Warehousing}'::text[]),
   ('11111111-0000-0000-0000-000000000043'::uuid, 'Manufacturing', 'Textiles', 'Medium', 'Business Unit', 'admin@kaveri.example.com', 'Supply fabric to garment exporters.', '{Weaving,Dyeing,Quality control}'::text[]),
   ('11111111-0000-0000-0000-000000000044'::uuid, 'Services', 'Accounting', 'Micro', 'Functional', 'admin@sterling.example.com', 'Keep clients compliant and their books current.', '{Bookkeeping,Tax filings,Audit}'::text[]),
   ('11111111-0000-0000-0000-000000000045'::uuid, 'Manufacturing', 'Food', 'Large', 'Business Unit', 'admin@greenfield.example.com', 'Packaged foods sold through distributors.', '{Processing,Packaging,Distribution}'::text[]),
   ('11111111-0000-0000-0000-000000000046'::uuid, 'Services', 'Others', 'Micro', 'Functional', 'admin@udaya.example.com', 'Skills training for young people.', '{Training programmes}'::text[])
  ) v(id, cat, sub, size, model, mail, obj, caps)
 WHERE company.user_id = v.id;

-- People join entities (admins first; Divya also works part-time with Kaveri)
INSERT INTO person_entity_link (person_id, company_user_id, dept_bu_id, role_id, is_full_time, is_entity_super_user, work_email, designation, sits, employer_approved)
SELECT v.p::uuid, v.e::uuid, (SELECT dept_bu_id FROM dept_bu WHERE company_user_id = v.e::uuid AND name = v.dept),
       (SELECT role_id FROM role_definition WHERE company_user_id = v.e::uuid AND name = v.role), v.ft, v.adm, v.mail, v.desig,
       CASE WHEN v.adm THEN 'Admin above Dept/BU head' ELSE 'Dept/BU head or below' END, true
  FROM (VALUES
   ('11111111-0000-0000-0000-000000000031', '11111111-0000-0000-0000-000000000041', 'Finance',    'Director',           true,  true,  'anil@brightline.example.com',  'Director'),
   ('11111111-0000-0000-0000-000000000032', '11111111-0000-0000-0000-000000000041', 'Finance',    'Executive',          true,  false, 'fatima@brightline.example.com','Accounts Executive'),
   ('11111111-0000-0000-0000-000000000033', '11111111-0000-0000-0000-000000000042', 'Operations', 'Designated Partner', true,  true,  'karthik@novalogistics.example.com', 'Designated Partner'),
   ('11111111-0000-0000-0000-000000000034', '11111111-0000-0000-0000-000000000043', 'Operations', 'Director',           true,  true,  'leena@kaveri.example.com',     'Director'),
   ('11111111-0000-0000-0000-000000000035', '11111111-0000-0000-0000-000000000044', 'Finance',    'Partner',            true,  true,  'suresh@sterling.example.com',  'Partner'),
   ('11111111-0000-0000-0000-000000000036', '11111111-0000-0000-0000-000000000044', 'Finance',    'Executive',          true,  false, 'divya@sterling.example.com',   'Senior Accountant'),
   ('11111111-0000-0000-0000-000000000036', '11111111-0000-0000-0000-000000000043', 'Finance',    'Manager',            false, false, 'divya@kaveri.example.com',     'Accounts (part-time)'),
   ('11111111-0000-0000-0000-000000000037', '11111111-0000-0000-0000-000000000045', 'Finance',    'Director',           true,  true,  'rahul@greenfield.example.com', 'Director'),
   ('11111111-0000-0000-0000-000000000038', '11111111-0000-0000-0000-000000000046', 'Operations', 'Trustee',            true,  true,  'sneha@udaya.example.com',      'Trustee')
  ) v(p, e, dept, role, ft, adm, mail, desig);

-- Person Personas
INSERT INTO person_persona (person_id, professional_identity, skills, experience, functional_interests, working_preferences) VALUES
 ('11111111-0000-0000-0000-000000000035', 'Practising chartered accountant', '{Tax filings,Statutory audit,Reconciliations}', '18 years in practice', '{Indirect tax,Income tax}', 'Reviews in the morning'),
 ('11111111-0000-0000-0000-000000000034', 'Textile production head', '{Quality control,Vendor development}', '15 years in weaving and dyeing', '{Process improvement}', NULL),
 ('11111111-0000-0000-0000-000000000033', 'Logistics operations lead', '{Fleet planning,Route costing}', '10 years in road freight', '{}', 'Calls over email');

-- Work Personas for Brightline's Finance
DO $$
DECLARE e uuid := '11111111-0000-0000-0000-000000000041'; fin uuid; g1 uuid; g2 uuid; head uuid; exe uuid;
BEGIN
  SELECT dept_bu_id INTO fin FROM dept_bu WHERE company_user_id = e AND name = 'Finance';
  INSERT INTO grade (dept_bu_id, name, rank) VALUES (fin, 'Head', 1) RETURNING grade_id INTO g1;
  INSERT INTO grade (dept_bu_id, name, rank) VALUES (fin, 'Executive', 2) RETURNING grade_id INTO g2;
  INSERT INTO work_persona (entity_id, dept_bu_id, grade_id, name, modules, actions)
  VALUES (e, fin, g1, 'Finance Head', ARRAY['WOM','Krama','Catalogue','Vendors','Reports'], ARRAY['View','Approve','Sign']) RETURNING persona_id INTO head;
  INSERT INTO work_persona (entity_id, dept_bu_id, grade_id, name, reports_to, modules, actions)
  VALUES (e, fin, g2, 'Accounts Executive', head, ARRAY['WOM','Catalogue','Vendors'], ARRAY['View']) RETURNING persona_id INTO exe;
  UPDATE person_entity_link SET persona_id = exe WHERE company_user_id = e AND person_id = '11111111-0000-0000-0000-000000000032';
END $$;

-- ---------- catalogue items in the new domains ----------
DO $$
BEGIN
  PERFORM create_catalogue_item('11111111-0000-0000-0000-000000000042', '11111111-0000-0000-0000-000000000033',
    '{"catalogue":"Commercial","domain_persona_id":"d1000000-0000-0000-0000-000000000011","name":"Freight forwarding","item_type":"Services"}');
  PERFORM create_catalogue_item('11111111-0000-0000-0000-000000000043', '11111111-0000-0000-0000-000000000034',
    '{"catalogue":"Commercial","domain_persona_id":"d1000000-0000-0000-0000-000000000012","name":"Yarn supply","item_type":"SKU"}');
  PERFORM create_catalogue_item('11111111-0000-0000-0000-000000000043', '11111111-0000-0000-0000-000000000034',
    '{"catalogue":"Process","domain_persona_id":"d1000000-0000-0000-0000-000000000014","name":"Incoming inspection","item_type":"Services"}');
  PERFORM create_catalogue_item('11111111-0000-0000-0000-000000000044', '11111111-0000-0000-0000-000000000035',
    '{"catalogue":"Commercial","domain_persona_id":"d1000000-0000-0000-0000-000000000001","name":"Monthly bookkeeping","item_type":"Services"}');
  PERFORM create_catalogue_item('11111111-0000-0000-0000-000000000044', '11111111-0000-0000-0000-000000000035',
    '{"catalogue":"Compliance","domain_persona_id":"d1000000-0000-0000-0000-000000000015","name":"TDS return filing","item_type":"Services"}');
  PERFORM create_catalogue_item('11111111-0000-0000-0000-000000000045', '11111111-0000-0000-0000-000000000037',
    '{"catalogue":"Process","domain_persona_id":"d1000000-0000-0000-0000-000000000013","name":"Payroll run","item_type":"Services"}');
  PERFORM create_catalogue_item('11111111-0000-0000-0000-000000000045', '11111111-0000-0000-0000-000000000037',
    '{"catalogue":"Compliance","domain_persona_id":"d1000000-0000-0000-0000-000000000016","name":"PF and ESI filing","item_type":"Services"}');
END $$;

-- ---------- connections between entities (relationship from the inviting side) ----------
INSERT INTO entity_connection (from_entity, to_entity, to_name, relationship, state) VALUES
 ('11111111-0000-0000-0000-000000000041', '11111111-0000-0000-0000-000000000012', 'Ledgerline Traders', 'Vendor', 'Connected'),
 ('11111111-0000-0000-0000-000000000043', '11111111-0000-0000-0000-000000000042', 'Nova Logistics',     'Vendor', 'Connected'),
 ('11111111-0000-0000-0000-000000000045', '11111111-0000-0000-0000-000000000044', 'Sterling & Co',      'Vendor', 'Connected'),
 ('11111111-0000-0000-0000-000000000043', '11111111-0000-0000-0000-000000000044', 'Sterling & Co',      'Vendor', 'Pending'),
 ('11111111-0000-0000-0000-000000000046', '11111111-0000-0000-0000-000000000044', 'Sterling & Co',      'Pre-vendor', 'Pending'),
 ('11111111-0000-0000-0000-000000000045', '11111111-0000-0000-0000-000000000042', 'Nova Logistics',     'Pre-vendor', 'Connected');

-- Personal documents and Compane IDs for the new people
UPDATE users SET compane_id = 'CMP-' || upper(substr(md5(user_id::text), 1, 6)), identity_verified = true
 WHERE user_type = 'Individual' AND compane_id IS NULL;
INSERT INTO personal_document (owner_id, kind, status, at)
SELECT u.user_id, k, CASE WHEN k = 'National ID' THEN 'Verified' ELSE 'Not connected' END, CASE WHEN k = 'National ID' THEN clock_timestamp() END
  FROM users u, unnest(ARRAY['National ID','Tax ID','Passport']) k
 WHERE u.user_type = 'Individual' AND NOT EXISTS (SELECT 1 FROM personal_document d WHERE d.owner_id = u.user_id);

-- Responsibilities on the new compliance items
INSERT INTO responsibility (entity_id, item_id, obligation, kind, person_id, vendor_id)
SELECT ci.company_user_id, ci.item_id, ci.name, v.kind, v.p::uuid, v.vend::uuid
  FROM catalogue_item ci JOIN (VALUES
   ('PF and ESI filing', 'Bearer', NULL, NULL),
   ('PF and ESI filing', 'Fulfiller', NULL, '11111111-0000-0000-0000-000000000044'),
   ('PF and ESI filing', 'Auditor', '11111111-0000-0000-0000-000000000037', NULL),
   ('TDS return filing', 'Bearer', NULL, NULL),
   ('TDS return filing', 'Fulfiller', '11111111-0000-0000-0000-000000000036', NULL),
   ('TDS return filing', 'Auditor', '11111111-0000-0000-0000-000000000035', NULL)
  ) v(item, kind, p, vend) ON v.item = ci.name;
