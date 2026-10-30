# Compane ER demo — FRD v3.0 (Krama doctrine aligned)

A local demo of FRD v3.0: PostgreSQL database, Java (Spring Boot) API, React screens.

## Run it with one click

- Mac: double-click **Start Compane Demo.command** (first time: right-click → Open)
- Windows: double-click **Start Compane Demo.bat**

It starts Docker Desktop if needed, builds and starts the demo, resets the demo data when the
database design has changed, and opens http://localhost:3000. To stop it, quit Docker Desktop.

## Screens (shaped like the Figma "Campane.ai" → Dashboard)

Brand: the approved logo (two-arc mark + wordmark, one unit). Personal pages carry **Yousr**; from Business onwards they carry **compane**. Colours are the approved platform palette only — grey, black and orange, with orange used as ink (text, thin rules, outlines), never as a filled area. Fonts: Source Serif 4 and Source Sans 3.

- **Header:** logo, Search, Email and Calendar icons, and the user menu (top right) — pick who you are **working as** there; the platform super-user also finds **Platform admin** (masters and raw tables) there.
- **Yousr (personal) pages:** Home and **Tasks** — a To do / Done board with your own tasks (add, priority, mark done, delete and restore) and personal-identifier requests from an entity (Give consent). In the Yousr side menu, **compane** (mark plus word, in menu style) takes you to Business; on the Business page, **Yousr** takes you back.
- **Personal Home** → **Business** (your entities) → open an entity.
- **Entity rail:** Home (quadrant list: Do now / Do later / Delegate / Delete, with All / With me / with others), Vendors, Catalogue, Task (list → task detail → topic), Settings (Krama console). Revenue, Compliance, Discover and Connect, Files, Tools and Projects open a "not in demo" page, as do Email, ID and personal Tasks and Files.
- **Task detail:** Topics / Decision / Agreed / Files; Setting up (seats), Internal space (Private and Shared rooms) and External space; open a topic to answer, review, agree, contest or deadlock, and to set each question's priority.

## Catalogue

Entity rail → Catalogue. **Owned** lists the entity's own items and **Borrowed** lists vendor items shared with it (published, External → Client, Generic or naming the entity); chips filter by Compliance / Process / Commercial. Each row shows Catalogue ID, type (SKU / SDU / Services), visibility, number of variants and release (Alpha → Pilot → Beta → General Availability); items stay **Unpublished** until their review (Share and Assign) closes as Success. **+ Add item** picks Compliance, Business › Process or Business › Commercial → Domain → Domain persona, or (Commercial) searches the library and uses an item as it is or customised.

Opening an item replaces the entity menu with the item's own: Overview (path, Domain persona metadata, owner from the Fulfiller seat, release, Kramas it runs), Visibility (External → Discover and Connect, Client or Vendor → Generic or Customised by name; Internal → Host Dept/BU → Internal client or Self), Variants (pricing type and tax, HSN/SAC, GST, quotation and invoice wording, one offer at a time, promo; add with "copy from"), Content (title, main image, text / image / video blocks), Report and Analytics (focus strip, sales by relationship, the Kramas' stages → topics → report questions; synthetic preview until runs exist), Marketing (landing page generated and approved, or an outside address; brand, category, competitors), Journey & Dependencies (one row per variant; Krama-level or catalogue-level dependencies, before or after, never blocking, "done outside the platform"; catalogue picks list Beta and General Availability only) and Seats (Buyer, Seller, Fulfiller, Assurer, Representation; the Fulfiller can map several vendors' items as a quote comparison; the Assurer is never the Fulfiller). Only the entity super-user edits; everyone else, and Borrowed items, read only. Overview also assigns and removes the Kramas the item runs: any Published Krama in the entity's pool, including one already on another item (removing one stops new starts; tasks already started keep it). Settings › Krama still starts tasks from an item and lists every Published Krama to assign or to add as a new item.

## Answering (Krama Phase 1)

Each question answers in the shape of its flow option: Decision (wording), Input field, Choice list (one or many), Checklist (a choice per item), File drop (file name, Mobile or Fixed, evidence), Assign (what was done, evidence), Table grid (rows, each Checked / Matched / Clear / Flagged; Flagged needs explanation and evidence), Compare box (two values, difference against a limit), Finding control (Clear or Flagged), Signature panel (version locks on signing). Allowed second answer types: File drop with Decision, Input field or Checklist; Finding control with Table grid or Compare box. A Contest round with reason Remove, once the answering side agrees, ends the question Cancelled — and a cancelled question no longer holds up the questions waiting on it. Files and signatures are recorded, not stored or signed for real.

## Rooms (Krama Phase 2)

In a task, the Requestor/Conductor can add more Internal and External rooms (+ Room). A new room starts with every topic its path allows Retained; "Delete from room" moves a topic's questions to another room of that kind, and a tally line warns while a topic sits in two rooms of one kind. A child External room forks from an External room, can be with another entity, and opens only once the other party in its parent room gives permission. Each room has Topics, a Registry (named registries holding events and files, entries with stage and status, files attached in answers, and the room's calendar inside it) and Members, plus one chat in the right column that can mention a question. Agreed answers travel to every room that retains their topic.

## Capabilities (Krama Phase 3)

The Krama console lists the capability catalogue; "+ Capability" on a stage, topic or question offers only those allowed at that boundary. Two are enforced in runs: Stage gate (later stages stay locked until the gated stage closes) and Maker-checker (a Reviewer must check before an answer is agreed); the rest are recorded and shown. A topic can be marked "Output document". In a task: "Send to a third party" on a Private or Internal question records the request and its reply; "Call in and split" brings an External-room answer into your own room as lines, with only the lines marked Under discussion to settle; the Reports tab shows output documents (progress, agreed lines, referenced files) and Estimation vs Execution (cost, price, margin, days; Borrowed lines show the vendor invite chain; Opportunity and Deal show Estimation only).

## Second UI: chat

User menu → Chat view. Sign-in and the personal chat are Yousr (personal space); choosing an entity in the menu switches the chat to compane, and Personal switches back. It opens empty: just the logo and the input box. The panel icon (top left) opens the menu: New chat, the entities, Classic view, who you are and Sign out (the sign-in page is Yousr, the personal side). The grid icon inside the text box lists the tools only: Calendar, Email, Chat, Files, Search. Every module and all data are reached by asking, in text or audio: ask in text, or switch to Audio and speak (Chrome or Edge; replies are read aloud). It understands: what's waiting on me, show my calendar for this week, show the catalogue, start <item> with <entity>, agree <item>, show my tasks, switch to <entity or person>, show the vendors, search <words>, open the Krama console, settings, help. Work arrives as cards — Agree, Contest, Show details, Start a task — and every change asks you to confirm first. The catalogue works in chat: each item shows its details and the Kramas it runs, and starting a task picks the relationship and counterparty and shows which Krama will run before you confirm. "Open" and "Show details" take you to the task in the classic view.

## Who to work as

| Person | Is | Try |
|---|---|---|
| Meera Iyer | Platform super-user | Krama console (platform Kramas), all Masters and tables |
| Vikram Shah | Ledgerline Traders, Finance, entity super-user; Requestor/Conductor of INS-0001 | Seats, approving stage 2, catalogue, entity pool, amend |
| Priya Nair | Ledgerline Traders, Finance | Reviewer (maker-checker) |
| Ravi Kumar | Ledgerline Traders, Finance (also part-time at Northwind) | Approver on stage 1, Doer on stage 2, Requestor of the Expense claims |
| Asha Rao | Northwind Supplies (the vendor), entity super-user | Doer and SPOC on stage 1, answers in the Vendor room (ER) |

## Demo examples — one of every scenario

| Scenario | Where to see it | Work as |
|---|---|---|
| Answer contested, waiting for the Doer to answer again | INS-0001 Vendor invoice approval → Vendor room → Delivery note | Asha Rao |
| Question locked, waiting for linked questions | INS-0001 → Internal room → Match invoice to purchase order | Vikram Shah |
| Answer waiting for the Reviewer (maker-checker) | INS-0005 Expense claim → Claim details | Priya Nair |
| Answer reviewed, waiting for the Approver | INS-0006 Vendor invoice approval → Vendor invoice | Ravi Kumar |
| Run Fulfilled and conserved | INS-0002 Expense claim; INS-0007 Connect entity | Ravi Kumar or Vikram Shah |
| Contest, then Deadlock (Dropped), rest Cancelled → Unfulfilled | INS-0003 Expense claim | Ravi Kumar or Vikram Shah |
| Conserved run amended (A1) with a reopened question | INS-0004 · A1 Expense claim → Approve reimbursement | Ravi Kumar |
| Platform Built Platform Owned, used as is | Connect entity in the Catalogue; INS-0007 | Vikram Shah |
| Platform built, imported and customised (Entity Customised) | Krama console → Vendor invoice approval (Ledgerline) | Vikram Shah |
| Platform built, imported unchanged (Platform built) | Krama console → Vendor invoice approval (Northwind) | Asha Rao |
| Entity Built Entity Owned | Expense claim (Ledgerline, Published); Purchase order approval (Northwind) | Vikram Shah / Asha Rao |
| Newer version available on the platform | Krama console → Ledgerline's Vendor invoice approval | Vikram Shah |
| Krama in Created / Learning and Training / Testing | Payment run (Ledgerline) / Vendor onboarding (platform) / Purchase order approval (Northwind) | Vikram / Meera / Asha |
| Published Krama frozen; New version | Any Published Krama in the Krama console | its owner |
| Person in two entities with the employer's approval | Masters → People and entities: Ravi Kumar (Ledgerline full-time, Northwind part-time) | Meera Iyer |
| Seats filtered by expertise | Any open run → Overview → Seats | the Requestor/Conductor |
| Standalone tasks in each quadrant, and one Done | Home → Standalone and Conserved | Vikram Shah; Ravi Kumar |
| Personal calendar | Home → Calendar | anyone |
| Two vendors of different persona types get different Kramas | Settings › Krama → Office supplies → Relationship Vendor → With Northwind Supplies (Trading and distribution) runs Vendor invoice approval; with Orbit IT Services (IT services and software) runs Service acceptance; as Client, none | Vikram Shah |
| Relationship matrix and persona types | Krama design → Relationship matrix; Masters → Persona types (from the live backend classification) | Meera Iyer |
| Catalogue library and entity instance | Masters → Catalogue domains, Domain personas, Catalogue library; Ledgerline → Catalogue → open an item (Overview, Visibility, Variants, Content, Report and Analytics, Marketing, Journey & Dependencies, Seats) | Meera Iyer / Vikram Shah |
| Borrowed catalogue | Ledgerline → Catalogue → Borrowed: Northwind's Office supplies (shared by name with Ledgerline); Ledgerline's own Office supplies maps it in its Fulfiller seat | Vikram Shah |
| History and audit | A run → History and audit | the Requestor/Conductor or Meera |

## What is in it

| FRD v3.0 | In the demo |
|---|---|
| Masters | Company Type (sub-type, structure) with standard Dept/BUs and role definitions copied into each company; Expertise; people linked to one or more entities (a full-time employee needs the employer's approval for another link); entity super-user |
| Krama design | Krama → Stage → Topic → Question, rooms PR / IR / ER, paths, flow options, Rules box, question links, Report and Analytics, expertise required (Consumer / Provider) |
| Ownership and lifecycle | Platform Built Platform Owned / Platform Built Entity Owned / Entity Built Entity Owned; Created → Learning and Training → Testing → Published; Published is frozen, New version for changes; import into the entity pool (Platform built → Entity Customised when edited); "Newer version available" |
| Connect | Platform catalogue library (SKU / SDU / Services with seller and buyer persona types); entity catalogue items (domain path, visibility, variants, content, marketing, journey and dependencies, seats, release and review) with assigned Kramas; Start picks the relationship and counterparty, and the relationship matrix decides which Krama runs |
| Conduct | Seats per stage (Doer, Reviewer, Approver, SPOC) as named people, filtered by expertise; Submit, Review (maker-checker), Agree, Contest (reason + explanation), Deadlock, Cancel, Reopen; questions wait for their linked questions; request and response by different people |
| Visibility | The room is the boundary: you see the rooms you are seated in and the questions asked there; an agreed answer travels to the other rooms on its topic's path |
| Conserve | When every question is closed the run ends Fulfilled or Unfulfilled, locks and is kept under its FY; Amend reopens it as INS-xxxx · A1 |
| Home | Questions to answer and to decide, Standalone tasks, a personal Calendar, conserved runs and done Standalone tasks |
| Standalone | One person's task in their entity: title, notes, due date, quadrant (Do now / Do later / Delegate / Delete); no rounds or approver; only the owner marks it Done, then it is conserved under the FY |
| Calendar | Personal: "Due" shows only where it is your turn (Doer while Pending or Contested, then Reviewer, then Approver / SPOC), plus your own Standalone tasks and what happened on questions you are seated on — for the super-user too |
| History and audit | Every action, for the Requestor/Conductor and the super-user |

Not in the demo: document reading (OCR / API sources are recorded but not performed), Standalone mode
links for off-platform counterparties, notifications (NEM), room chat and Registry files.

## Folders

| Folder | What it is |
|---|---|
| `db/` | `01_schema.sql` tables and rules on masters and design, `02_persona_types.sql` persona types from the live classification, `03_krama.sql` Krama actions, `04_seed.sql` demo data, `05_views.sql` what the screens read |
| `api/` | Java 17 Spring Boot API on port 8080 (`/api/...`; every call carries the `X-Acting-User` header) |
| `web/` | React screens served on port 3000 |

## Run from a terminal

    docker compose down -v
    docker compose up --build

Then open http://localhost:3000.

## Personas

- **Work Persona** decides what a person sees and may do in an entity: modules (WOM, Krama, Catalogue, Vendors, Connections, Revenue, Compliance, Reports) and actions (View, Approve, Sign). Entity admins have everything; a person with no Work Persona has WOM and View. The entity menu, Settings tabs and the chat view follow it; seating someone as Approver needs Approve, and signing a version needs Sign. Settings › Work Personas: grades and personas per Dept/BU, Edit (modules, actions, authority seat), and each person's Work Persona.
- **Authority seats** (Settings): from the legal form, with the minimum and maximum set by law. A Work Persona attaches to a seat; it never creates one; a full seat takes nobody more.
- **Entity Persona** (Settings): the type, what it applies to, and its obligatory and non-obligatory lists; admins can change it.
- **Domain personas** (Settings, platform super-user): requirements, permissible, not permissible and seats on each domain persona; a catalogue item's Overview shows its definition.
- **Human Persona**: a person counterparty resolves Kramas through the person's persona type (types still to be defined).

## Chat view (merged in)

User menu → Chat view. It uses the base-UI frame: a spaces rail (Personal and each entity; you at the bottom with Settings in four sections — Entity, User and Access, Plan and Usage, Entity Data — Classic view, New chat, Sign out), pages and tools opening in the content pane beside the chat, and the composer with the tools tray (Calendar, Email, Chat, Files, Search), microphone and send; on a phone, Content and Chat are tabs. "Show the catalogue" opens this copy's catalogue (Owned / Borrowed, the item pages). Type "help" for everything you can ask: sign-in with a code, Create Entity, invites, connections, Settings in full, reports, modules, components, personas and more. The classic view is unchanged.

Settings file: **yousr-settings.env** (Resend key and sender to email sign-in codes; SAMPLE_PEOPLE=true shows the sample people on the sign-in page).

## Persona, Role, Responsibility and Permission (kept separate)

- **Work Persona** — role, responsibility and permission in one, set under the person's Dept/BU: grade, reports to, authority seat, modules (WOM, Krama, Catalogue, Vendors, Connections, Revenue, Compliance, Reports) and actions (View, Approve, Sign). One person in one entity has one Work Persona. The entity admin and each Dept/BU's admin set them; entity admins have everything.
- **Person Persona** — the person's professional identity, skills, areas of expertise (the same expertise seats match against), experience, functional interests, working and communication preferences. Settings › My Person Persona (and Profile in the chat view's personal space).
- **Domain Profile** — each domain's objectives, terminology, regulations, typical workflows, domain-specific knowledge, controls and compliance requirements, above its domain personas (platform super-user: Settings › Domain profiles and personas).
- **Entity Profile** — business objectives, functional capabilities, areas of operation and business interests, shown with the Entity Persona and in each task's Context.
- **Responsibility** — for each obligation, the bearer (the entity), fulfiller and auditor named against a person or vendor; the auditor is never the fulfiller. Settings › Responsibilities.
- **Role** — unchanged: task seats (Doer, Reviewer, Approver, SPOC) and catalogue item seats.

**Platform Kramas:** the platform super-user opens **Krama console** from the user menu (top right; also first in Platform admin), or asks "Krama console" in the chat view from the personal space.

## Sample data

Entities across domains: Ledgerline Traders and Brightline Retail (Trading › Retail), Northwind Supplies (Trading › Wholesale / Distribution), Orbit IT Services (Services › Technology Services), Nova Logistics (Services › Business Operations Services), Sterling & Co (Services › Professional services firm), Kaveri Textiles (Manufacturing › Discrete Manufacturing), Greenfield Foods (Manufacturing › Process Manufacturing) and Udaya Foundation (Other › Non-profit). People: Vikram Shah, Ravi Kumar, Priya Nair, Asha Rao, Meera Iyer (platform super-user), Anil Mehta, Fatima Shaikh, Karthik Rao, Leena D'Souza, Suresh Pillai, Divya Menon (also part-time at Kaveri), Rahul Verma and Sneha Kulkarni. Domains include Logistics services, Raw materials, Payroll, Quality control, Income tax and Labour law, with domain personas, profiles, catalogue items, connections and responsibilities.

## Stage context (Person Persona, Domain Profile, Entity Profile in a task)

In the Krama console each stage names its **Domain profile** (a topic or question can name a different one) and, per seat (Doer, Reviewer, Approver), the **person persona needed**: areas of expertise and skills. New version and Import carry these across; a Published Krama stays frozen. In a task, **Context** (under the task header, in both views) shows whose work it is (the Entity Profile), each stage's domain profile and what each seat needs. When seating, people who match are listed with what matched; a seated person who does not match is flagged "does not match the persona needed" — flagged, never blocked.

## Dept/BU profile, Module list and domain controls

- **Dept/BU profile** (Settings › Work Personas, on each Dept/BU): objectives, capabilities, areas of operation, business interests; the head persona and headcount show beside it.
- **Module** on Create Krama is now picked from a list (Opportunity, Deal, Order management, Network, Process); the platform super-user can add to it.
- **Domain controls applied**: each stage's domain profile controls are checks the task confirms ("Controls to confirm" under the task header). The stage's Reviewer or Approver, or the Requestor/Conductor, ticks them; a gated stage waits for its controls, and the task closes only when every control is confirmed.

## Online (Supabase + Netlify)

The API runs on your Yousr Supabase project. To put this copy online: drag the **yousr-web** folder onto app.netlify.com/drop, then open your web address + **/setup.html** and press **Set up the database** (once). Sign-in codes go by email once RESEND_API_KEY and RESEND_FROM are set in Supabase → Edge Functions → Secrets.

## User journeys (living document)

- **Register**: email → code → you land in Personal (Yousr) with your Compane ID and a task **Update your personal profile** (name, photo). No password, no other details at registration.
- **Register an entity**: the Business page (and the chat's Personal space) prompts **Add your business** when you have none; Create Entity follows, then setup.
- **Settings › Work Personas**: put people in a Dept/BU, make one person the **Dept/BU admin** (one per Dept/BU), and set Work Personas. The entity admin does everything; a Dept/BU admin sets personas, grades and personas for their own Dept/BU.
- **Client listing**: a new entity's admin gets the task **Complete your client listing** on the entity's Home. Type the client's name: businesses already on compane show as you type — pick one (user name and email optional) and a connection request goes to them; or choose "Not found? Add as a new client" (client entity name, user name, user email), listed until they join. A business already in the list cannot be added twice.
- **Catalogue**: the entity admin or a Dept/BU admin adds items; a Dept/BU admin's items belong to their Dept/BU, and they edit only those.

## Clients see a vendor's catalogue

A client sees a vendor's Published item under **Borrowed** when the item's Visibility is External → Client (Generic, or Customised naming the client) and the two are vendor and client: a task already ran between them, or their connection is **Connected**. A client listing or invite stays Pending until the client's admin accepts it — in the chat view (ask "Connections") or the classic view (the entity's **Discover and Connect** page): Send code, type it, Validate.

**Only reachable businesses are offered.** A business with nobody who can accept (no entity admin yet) never shows in Discover, Connect or the client search, cannot be invited, and a client listing by its name stays a listed client (not linked) until someone there can accept. Sample: Nikhil Joshi is Orbit IT Services' admin.
