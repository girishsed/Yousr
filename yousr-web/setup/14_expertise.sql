-- More areas of expertise, matched to the sample domains (platform master; the super-user maintains it)
INSERT INTO expertise (name, role, purpose) VALUES
 ('Indirect tax', 'Prepares and reviews indirect tax returns', 'Keeps indirect tax filings correct and on time'),
 ('Direct tax', 'Handles income tax, TDS and advance tax', 'Keeps direct tax deductions and returns correct'),
 ('Company law', 'Handles registrar filings and board matters', 'Keeps the entity compliant with company law'),
 ('Labour law compliance', 'Handles PF, ESI and labour returns', 'Keeps statutory contributions and returns correct'),
 ('Payroll', 'Computes and processes salaries', 'Pays people correctly and on time'),
 ('Accounts payable', 'Books and pays vendor invoices', 'Pays vendors correctly against matched documents'),
 ('Procurement', 'Raises and manages purchase orders', 'Buys at agreed terms from approved vendors'),
 ('Vendor management', 'Onboards and reviews vendors', 'Keeps the vendor base reliable and compliant'),
 ('Quality inspection', 'Inspects material and output against specifications', 'Accepts only material that meets the specification'),
 ('Logistics', 'Plans and tracks the movement of goods', 'Moves goods on time with proof of delivery'),
 ('IT support', 'Supports devices, systems and users', 'Keeps systems working for the business'),
 ('Internal audit', 'Tests controls and processes', 'Gives assurance that controls work')
ON CONFLICT (name) DO NOTHING;
