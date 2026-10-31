-- =====================================================================================
-- Keywords: the words people type, what each opens, and what the Work Persona needs.
-- Kept under Masters so the platform super-user edits them in the app; the chat reads them live.
-- Each person's own learned wordings (learned_phrase) still come first.
-- =====================================================================================
CREATE TABLE IF NOT EXISTS keyword (
  keyword_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  section    text NOT NULL,
  words      text NOT NULL,           -- what people type, comma separated
  opens      text NOT NULL,           -- the ask the chat runs for them
  space      text NOT NULL DEFAULT 'Both' CHECK (space IN ('Personal','Entity','Both')),
  needs      text,                    -- a module or action of the Work Persona, if any
  side       text CHECK (side IN ('Sell side','Buy side')),
  status     text NOT NULL DEFAULT 'Works' CHECK (status IN ('Works','To add'))
);

CREATE OR REPLACE FUNCTION api_keywords(actor uuid, b jsonb) RETURNS json LANGUAGE sql STABLE AS $$
  SELECT COALESCE(json_agg(json_build_object('words', words, 'opens', opens, 'space', space, 'needs', needs, 'side', side, 'status', status)), '[]')
    FROM keyword WHERE actor IS NOT NULL
$$;

INSERT INTO keyword (section, words, opens, space, needs, side, status)
SELECT * FROM (VALUES
  ('Personal space', 'my tasks, personal tasks, add task, consent', 'my tasks', 'Personal', NULL, NULL, 'Works'),
  ('Personal space', 'my id, identity, my documents', 'my id', 'Personal', NULL, NULL, 'Works'),
  ('Personal space', 'profile, my details, personal settings', 'profile', 'Personal', NULL, NULL, 'Works'),
  ('Personal space', 'create an entity, new company, register a business', 'create an entity', 'Both', NULL, NULL, 'Works'),
  ('Personal space', 'invites, join an entity', 'my invites', 'Both', NULL, NULL, 'Works'),
  ('Personal space', 'my entities, my businesses, my companies', 'my entities', 'Both', NULL, NULL, 'Works'),
  ('Personal space', 'discover, find a provider, marketplace', 'discover and connect', 'Both', NULL, NULL, 'Works'),
  ('Entity work and priorities', 'what''s waiting, what''s waiting on me, pending, to do, due, today, my work', 'what''s waiting on me?', 'Both', 'WOM', NULL, 'Works'),
  ('Entity work and priorities', 'show my tasks, tasks, runs, jobs', 'show my tasks', 'Entity', 'WOM', NULL, 'Works'),
  ('Entity work and priorities', 'new task, standalone task', 'new standalone task', 'Entity', 'WOM', NULL, 'Works'),
  ('Entity work and priorities', 'home, overview, focus, dashboard', 'home', 'Entity', 'WOM', NULL, 'Works'),
  ('Entity work and priorities', 'urgent, do now, overdue', 'urgent', 'Entity', 'WOM', NULL, 'To add'),
  ('Entity work and priorities', 'delegated, with others, waiting on others', 'delegated', 'Entity', 'WOM', NULL, 'To add'),
  ('Clients — sell side', 'clients, customers, buyers, who we sell to', 'clients', 'Both', 'Connections', 'Sell side', 'Works'),
  ('Clients — sell side', 'pre-clients, leads, prospects', 'pre-clients', 'Entity', 'Connections', 'Sell side', 'To add'),
  ('Clients — sell side', 'connect a client, invite a client, add a client', 'connections', 'Entity', 'Connections', 'Sell side', 'Works'),
  ('Clients — sell side', 'enquiry, opportunity, proposal, quote for a client', 'opportunity', 'Entity', 'Opportunity', 'Sell side', 'To add'),
  ('Clients — sell side', 'orders, client orders, sales orders', 'sales orders', 'Entity', 'Order management', 'Sell side', 'To add'),
  ('Vendors — buy side', 'vendors, suppliers, sellers, who we buy from', 'vendors', 'Both', 'Vendors', 'Buy side', 'Works'),
  ('Vendors — buy side', 'pre-vendors, shortlisted vendors', 'pre-vendors', 'Entity', 'Vendors', 'Buy side', 'To add'),
  ('Vendors — buy side', 'connect a vendor, invite a vendor, add a vendor', 'connections', 'Entity', 'Connections', 'Buy side', 'Works'),
  ('Vendors — buy side', 'requirement, deal, ask for a quote, compare quotes', 'deal', 'Entity', 'Deal', 'Buy side', 'To add'),
  ('Vendors — buy side', 'orders, purchase orders, vendor orders', 'purchase orders', 'Entity', 'Order management', 'Buy side', 'To add'),
  ('Catalogue', 'catalogue, products, services, items, what we sell', 'show the catalogue', 'Entity', 'Catalogue', NULL, 'Works'),
  ('Catalogue', 'manage the catalogue, edit the catalogue, add an item', 'manage the catalogue', 'Entity', 'Catalogue', NULL, 'Works'),
  ('Catalogue', 'borrowed items, vendor items', 'borrowed items', 'Entity', 'Catalogue', NULL, 'To add'),
  ('Krama', 'krama, krama console, console, workflow, process builder', 'krama console', 'Entity', 'Krama', NULL, 'Works'),
  ('Krama', 'modules, modules and reports, report and analytics krama', 'modules and reports', 'Entity', 'Krama', NULL, 'Works'),
  ('Krama', 'components, building blocks', 'components', 'Entity', 'Krama', NULL, 'Works'),
  ('Krama', 'new krama, create a workflow', 'new krama', 'Entity', 'Krama', NULL, 'To add'),
  ('Krama', 'testing, learning and training, published', 'krama by status', 'Entity', 'Krama', NULL, 'To add'),
  ('Money, reports and compliance', 'revenue, sales', 'revenue', 'Entity', 'Revenue', NULL, 'Works'),
  ('Money, reports and compliance', 'reports, analytics, numbers, mis', 'reports', 'Entity', 'Reports', NULL, 'Works'),
  ('Money, reports and compliance', 'estimation, execution, output document', 'estimation', 'Entity', 'WOM', NULL, 'Works'),
  ('Money, reports and compliance', 'compliance, filings, statutory, returns due', 'compliance', 'Entity', 'Compliance', NULL, 'Works'),
  ('Money, reports and compliance', 'what''s due to file, overdue filings', 'overdue filings', 'Entity', 'Compliance', NULL, 'To add'),
  ('Approve, sign and other actions', 'approve, approvals, waiting for my approval', 'approvals', 'Entity', 'Approve', NULL, 'To add'),
  ('Approve, sign and other actions', 'sign, to sign, signatures', 'to sign', 'Entity', 'Sign', NULL, 'To add'),
  ('Approve, sign and other actions', 'send back, release', 'send back', 'Entity', 'WOM', NULL, 'To add'),
  ('Tools', 'calendar, my calendar, schedule, meetings', 'calendar', 'Both', NULL, NULL, 'Works'),
  ('Tools', 'calendar this week, this week''s items', 'show my calendar for this week', 'Both', NULL, NULL, 'Works'),
  ('Tools', 'email, inbox, mail', 'email', 'Both', NULL, NULL, 'Works'),
  ('Tools', 'chat, messages', 'chat', 'Both', NULL, NULL, 'Works'),
  ('Tools', 'files, documents, attachments', 'files', 'Both', NULL, NULL, 'Works'),
  ('Settings, people and access', 'settings, entity settings', 'settings', 'Entity', NULL, NULL, 'Works'),
  ('Settings, people and access', 'users, people, user and access, team', 'user and access', 'Entity', NULL, NULL, 'Works'),
  ('Settings, people and access', 'entity persona, what applies to us', 'entity persona', 'Entity', NULL, NULL, 'Works'),
  ('Settings, people and access', 'seats, authority, authority seats', 'authority seats', 'Entity', NULL, NULL, 'Works'),
  ('Settings, people and access', 'my access, what can i do', 'my access', 'Entity', NULL, NULL, 'To add'),
  ('Settings, people and access', 'masters, platform admin, tables', 'masters', 'Both', NULL, NULL, 'Works'),
  ('Settings, people and access', 'domain personas', 'domain personas', 'Both', NULL, NULL, 'Works')
) v(section, words, opens, space, needs, side, status)
WHERE NOT EXISTS (SELECT 1 FROM keyword);

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    ALTER TABLE public.keyword ENABLE ROW LEVEL SECURITY;
    REVOKE ALL ON public.keyword FROM anon, authenticated;
    REVOKE EXECUTE ON FUNCTION api_keywords(uuid, jsonb) FROM anon, authenticated, public;
  END IF;
END $$;
