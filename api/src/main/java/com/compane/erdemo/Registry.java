package com.compane.erdemo;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Single source of truth for every table in the FRD v3.0 model.
 * The API only touches tables and columns listed here, and the UI builds its table screens from it.
 */
public final class Registry {

    /** Column types understood by the API and UI. */
    public enum Type { UUID, TEXT, LONGTEXT, DATE, INT, BOOL, STATUS, UUIDS, ENUM, ENUMS }

    /**
     * @param options allowed values for ENUM / ENUMS
     * @param filter  for links to users: only users of this user_type are offered
     * @param expr      a read-only value worked out by the database (never written)
     * @param dependsOn another field in the same form that must be chosen first; this list then only
     *                  offers rows whose {@code matchKey} equals that choice
     * @param matchKey  the column on the referenced rows compared with {@code dependsOn}
     * @param virtual   a choice that only narrows other lists; it is never saved
     */
    public record Col(String name, String label, Type type, String ref, boolean required,
                      List<String> options, String filter, String expr,
                      String dependsOn, String matchKey, boolean virtual) {
        Col(String name, String label, Type type, String ref, boolean required, List<String> options, String filter) {
            this(name, label, type, ref, required, options, filter, null, null, null, false);
        }
        Col(String name, String label, Type type, String ref, boolean required, List<String> options, String filter, String expr) {
            this(name, label, type, ref, required, options, filter, expr, null, null, false);
        }
        /** The same field, offering only rows whose matchKey equals the choice made in dependsOn. */
        Col after(String parent, String key) {
            return new Col(name, label, type, ref, required, options, filter, expr, parent, key, false);
        }
    }

    /** A choice that only narrows the lists after it (e.g. pick the Krama, then only its stages). Never saved. */
    private static Col narrowBy(String n, String l, String ref) {
        return new Col(n, l, Type.UUID, ref, false, null, null, null, null, null, true);
    }

    private static Col hidden(String n, String sql) { return new Col(n, "", Type.TEXT, null, false, null, null, sql); }

    public record Ent(String key, String table, String pk, String pkLabel, String label,
                      String group, List<String> display, String orderBy, List<Col> cols) {}

    /** Kept for the generic STATUS type (the four phases). */
    public static final List<String> STATUSES = List.of("Create", "Connect", "Conduct", "Conserve");
    public static final List<String> USER_TYPES = List.of("Individual", "Company", "AI");
    public static final List<String> SUB_TYPES = List.of(
            "Sole proprietor", "Partnership firm", "Pvt Ltd", "LLP", "Public Ltd", "Trust");
    public static final List<String> STRUCTURES = List.of("Functional", "Business Unit");
    public static final List<String> MAPPED_AS = List.of("Consumer", "Provider");
    public static final List<String> OWNERSHIP = List.of(
            "Platform Built Platform Owned", "Platform Built Entity Owned", "Entity Built Entity Owned");
    public static final List<String> PATHS = List.of("PR only", "PR → IR", "PR → IR → ER");
    public static final List<String> ROOM_KINDS = List.of("PR", "IR", "ER");
    public static final List<String> FLOW_OPTIONS = List.of("Decision", "Input field", "Choice list", "Checklist", "File drop",
            "Assign", "Table grid", "Compare box", "Finding control", "Signature panel");
    public static final List<String> ALSO_NEEDS = List.of("File drop", "Finding control");
    public static final List<String> TAG_KINDS = List.of("Business", "Compliance");
    public static final List<String> RELATIONSHIPS = List.of("Department", "Business Unit", "Pre-client", "Client", "Pre-vendor", "Vendor");
    public static final List<String> PARTY_TYPES = List.of("Entity", "Person");
    public static final List<String> LIBRARY_KINDS = List.of("SKU", "SDU", "Services");
    public static final List<String> CATALOGUES = List.of("Compliance", "Process", "Commercial");
    public static final List<String> RELEASES = List.of("Alpha", "Pilot", "Beta", "General Availability");
    public static final List<String> SEATS = List.of("Doer", "Reviewer", "Approver", "SPOC");
    public static final List<String> REASONS = List.of("Error found", "Incomplete", "Evidence missing", "Disagree", "Remove", "Other");
    public static final List<String> SOURCES = List.of("Platform data", "API", "OCR", "Person");

    /** Krama design tables: written by the platform super-user (platform Kramas) or the entity super-user (own pool). */
    public static final Set<String> DESIGN = Set.of(
            "krama", "room-template", "stage", "topic", "question", "question-link", "report", "expertise-required");

    /** Run tables change only through actions, never by plain edits. */
    public static final Set<String> READ_ONLY = Set.of(
            "catalogue-item", "catalogue-item-krama", "catalogue-variant", "catalogue-seat", "run", "room", "room-member", "seat", "question-run", "answer-round", "audit-log");

    /** Tables everyone may read (for pickers); the rest are for the platform super-user. */
    public static final Set<String> OPEN_TO_ALL = Set.of("users", "expertise", "persona-type", "library-item", "catalogue-domain", "domain-persona");

    private static final Map<String, Ent> ENTITIES = new LinkedHashMap<>();

    private static Col c(String n, String l, Type t) { return new Col(n, l, t, null, false, null, null); }
    private static Col req(String n, String l, Type t) { return new Col(n, l, t, null, true, null, null); }
    private static Col fk(String n, String l, String ref, boolean required) {
        return new Col(n, l, Type.UUID, ref, required, null, null);
    }
    private static Col userOf(String n, String l, String userType, boolean required) {
        return new Col(n, l, Type.UUID, "users", required, null, userType);
    }
    private static Col manyOf(String n, String l, String ref) { return new Col(n, l, Type.UUIDS, ref, false, null, null); }
    private static Col pick(String n, String l, List<String> options) { return new Col(n, l, Type.ENUM, null, true, options, null); }
    private static Col maybe(String n, String l, List<String> options) { return new Col(n, l, Type.ENUM, null, false, options, null); }

    private static void add(Ent e) { ENTITIES.put(e.key(), e); }

    static {
        // ---------- Masters ----------
        add(new Ent("expertise", "expertise", "expertise_id", "Expertise ID", "Expertise", "Masters",
                List.of("name"), "name",
                List.of(req("name", "Name", Type.TEXT), c("role", "Role", Type.LONGTEXT), c("purpose", "Purpose", Type.LONGTEXT))));

        add(new Ent("persona-type", "persona_type", "persona_type_id", "Persona type ID", "Persona types", "Masters",
                List.of("display_name"), "depth, display_name",
                List.of(req("slug", "Key", Type.TEXT), req("display_name", "Name", Type.TEXT),
                        pick("party_type", "Entity or Person", PARTY_TYPES),
                        fk("parent_id", "Broader type", "persona-type", false), c("depth", "Level", Type.INT),
                        c("description", "Description", Type.LONGTEXT))));

        add(new Ent("catalogue-domain", "catalogue_domain", "domain_id", "Domain ID", "Catalogue domains", "Masters",
                List.of("name"), "catalogue, name",
                List.of(pick("catalogue", "Catalogue", CATALOGUES), req("name", "Name", Type.TEXT))));

        add(new Ent("domain-persona", "domain_persona", "domain_persona_id", "Domain persona ID", "Domain personas", "Masters",
                List.of("name"), "name",
                List.of(fk("domain_id", "Domain", "catalogue-domain", true), req("name", "Name", Type.TEXT),
                        c("metadata", "Metadata", Type.LONGTEXT))));

        add(new Ent("library-item", "library_item", "library_item_id", "Library item ID", "Catalogue library", "Masters",
                List.of("name"), "kind, name",
                List.of(pick("kind", "SKU / SDU / Services", LIBRARY_KINDS), req("name", "Name", Type.TEXT),
                        c("metadata", "Metadata", Type.LONGTEXT), fk("domain_persona_id", "Domain persona", "domain-persona", false),
                        fk("seller_persona_type_id", "Seller persona type", "persona-type", false),
                        fk("buyer_persona_type_id", "Buyer persona type", "persona-type", false))));

        add(new Ent("company-type", "company_type", "company_type_id", "Company Type ID", "Company Type", "Masters",
                List.of("sub_type"), "sub_type",
                List.of(pick("sub_type", "Sub-type", SUB_TYPES), pick("structure", "Structure", STRUCTURES))));

        add(new Ent("company-type-dept-bu", "company_type_dept_bu", "id", "ID", "Company Type Dept/BU", "Masters",
                List.of("name"), "name",
                List.of(fk("company_type_id", "Company Type", "company-type", true), req("name", "Name", Type.TEXT))));

        add(new Ent("role-definition", "role_definition", "role_id", "Role ID", "Role definitions", "Masters",
                List.of("name"), "name",
                List.of(fk("company_type_id", "Company Type", "company-type", false),
                        userOf("company_user_id", "Company", "Company", false),
                        req("name", "Name", Type.TEXT), c("description", "Description", Type.LONGTEXT))));

        add(new Ent("users", "users", "user_id", "User ID", "Users", "Masters",
                List.of("name"), "name",
                List.of(req("name", "Name", Type.TEXT), c("personal_email", "Personal email", Type.TEXT),
                        pick("user_type", "User type", USER_TYPES), c("is_super_user", "Super-user", Type.BOOL),
                        manyOf("expertise_ids", "Expertise", "expertise"))));

        add(new Ent("company", "company", "company_id", "Company ID", "Company", "Masters",
                List.of("company_name"), "company_id",
                List.of(userOf("user_id", "User ID", "Company", true),
                        fk("company_type_id", "Company Type", "company-type", true),
                        fk("persona_type_id", "Persona type", "persona-type", false),
                        new Col("company_name", "", Type.TEXT, null, false, null, null,
                                "(SELECT u.name FROM users u WHERE u.user_id = company.user_id)"))));

        add(new Ent("dept-bu", "dept_bu", "dept_bu_id", "Dept/BU ID", "Dept/BU", "Masters",
                List.of("name", "company_name"), "name",
                List.of(userOf("company_user_id", "Company", "Company", true), req("name", "Name", Type.TEXT),
                        new Col("company_name", "", Type.TEXT, null, false, null, null,
                                "(SELECT u.name FROM users u WHERE u.user_id = dept_bu.company_user_id)"),
                        new Col("members", "Members", Type.TEXT, null, false, null, null,
                                "(SELECT string_agg(user_name(l.person_id), ', ') FROM person_entity_link l WHERE l.dept_bu_id = dept_bu.dept_bu_id)"))));

        add(new Ent("person-entity-link", "person_entity_link", "link_id", "Link ID", "People and entities", "Masters",
                List.of(), "link_id",
                List.of(userOf("person_id", "Person", "Individual", true),
                        userOf("company_user_id", "Entity", "Company", true),
                        fk("dept_bu_id", "Dept/BU", "dept-bu", false).after("company_user_id", "company_user_id"),
                        fk("role_id", "Role", "role-definition", false).after("company_user_id", "company_user_id"),
                        c("is_full_time", "Full-time", Type.BOOL),
                        c("employer_approved", "Employer approved", Type.BOOL),
                        c("is_entity_super_user", "Entity super-user", Type.BOOL))));

        // ---------- Krama design (Create) ----------
        add(new Ent("krama", "krama", "krama_id", "Version ID", "Krama", "Krama design",
                List.of("name", "version_label"), "name",
                List.of(req("code", "Krama ID", Type.TEXT), req("name", "Name", Type.TEXT),
                        userOf("owner_entity", "Owner entity", "Company", false),
                        pick("ownership_type", "Ownership type", OWNERSHIP),
                        c("pool_mark", "Pool mark", Type.TEXT), c("status", "Status", Type.TEXT),
                        c("version", "Version", Type.INT),
                        maybe("tag_kind", "Business or Compliance", TAG_KINDS),
                        c("tag_domain", "Module", Type.TEXT),
                        c("lifetime_years", "Lifetime (years)", Type.INT),
                        c("what_changed", "What changed", Type.LONGTEXT),
                        new Col("version_label", "", Type.TEXT, null, false, null, null, "('v' || krama.version)"))));

        add(new Ent("room-template", "room_template", "room_template_id", "Room ID", "Rooms", "Krama design",
                List.of("label"), "kind",
                List.of(fk("krama_id", "Krama", "krama", true), pick("kind", "Kind", ROOM_KINDS), req("label", "Name", Type.TEXT))));

        add(new Ent("stage", "stage", "stage_id", "Stage ID", "Stages", "Krama design",
                List.of("name"), "seq",
                List.of(fk("krama_id", "Krama", "krama", true), req("name", "Name", Type.TEXT),
                        c("seq", "Order", Type.INT), pick("path", "Path", PATHS))));

        add(new Ent("topic", "topic", "topic_id", "Topic ID", "Topics", "Krama design",
                List.of("name"), "seq",
                List.of(narrowBy("krama_pick", "Krama", "krama"),
                        fk("stage_id", "Stage", "stage", true).after("krama_pick", "krama_id"), req("name", "Name", Type.TEXT),
                        c("seq", "Order", Type.INT), pick("path", "Path", PATHS), c("is_output", "Output document", Type.BOOL),
                        hidden("krama_id", "(SELECT s.krama_id FROM stage s WHERE s.stage_id = topic.stage_id)"))));

        add(new Ent("question", "question", "question_id", "Question ID", "Questions", "Krama design",
                List.of("text"), "seq",
                List.of(narrowBy("krama_pick", "Krama", "krama"),
                        fk("topic_id", "Topic", "topic", true).after("krama_pick", "krama_id"), req("text", "Question", Type.TEXT),
                        c("seq", "Order", Type.INT), pick("flow_option", "Flow option", FLOW_OPTIONS),
                        pick("ask_in", "Asked in", ROOM_KINDS), c("rules", "Rules", Type.LONGTEXT),
                        c("due_days", "Due in (days)", Type.INT),
                        c("setup_options", "Options or checklist items (one per line)", Type.LONGTEXT),
                        c("setup_choices", "Checklist choices (one per line)", Type.LONGTEXT),
                        c("setup_multi", "Choice list: pick many", Type.BOOL),
                        c("setup_columns", "Table grid columns (one per line)", Type.LONGTEXT),
                        c("setup_limit", "Compare box: allowed difference", Type.INT),
                        maybe("also_needs", "Also needs", ALSO_NEEDS),
                        hidden("krama_id", "(SELECT s.krama_id FROM topic t JOIN stage s USING (stage_id) WHERE t.topic_id = question.topic_id)"))));

        add(new Ent("question-link", "question_link", "link_id", "Link ID", "Question links", "Krama design",
                List.of(), "link_id",
                List.of(narrowBy("krama_pick", "Krama", "krama"),
                        fk("question_id", "Question", "question", true).after("krama_pick", "krama_id"),
                        fk("predecessor_id", "Waits for", "question", true).after("krama_pick", "krama_id"))));

        add(new Ent("report", "report", "report_id", "Report ID", "Report and Analytics", "Krama design",
                List.of("name"), "name",
                List.of(fk("krama_id", "Krama", "krama", true), req("name", "Name", Type.TEXT),
                        req("question_text", "What it answers", Type.LONGTEXT))));

        add(new Ent("krama-relationship", "krama_relationship", "id", "Row ID", "Relationship matrix", "Krama design",
                List.of("relationship"), "relationship",
                List.of(fk("krama_id", "Krama", "krama", true), pick("relationship", "Relationship", RELATIONSHIPS),
                        pick("party_type", "Entity or Person", PARTY_TYPES), fk("persona_type_id", "Persona type", "persona-type", true))));

        add(new Ent("expertise-required", "expertise_required", "requirement_id", "Requirement ID", "Expertise required",
                "Krama design", List.of("mapped_as"), "mapped_as",
                List.of(narrowBy("krama_pick", "Krama", "krama"),
                        fk("stage_id", "Stage", "stage", false).after("krama_pick", "krama_id"),
                        fk("topic_id", "Topic", "topic", false).after("krama_pick", "krama_id"),
                        fk("question_id", "Question", "question", false).after("krama_pick", "krama_id"),
                        fk("expertise_id", "Expertise", "expertise", true),
                        pick("mapped_as", "Mapped as", MAPPED_AS))));

        // ---------- Runs (Connect, Conduct, Conserve) ----------
        add(new Ent("catalogue-item", "catalogue_item", "item_id", "Item ID", "Catalogue items", "Runs",
                List.of("catalogue_code", "name"), "catalogue_code",
                List.of(userOf("company_user_id", "Entity", "Company", true), c("catalogue_code", "Catalogue ID", Type.TEXT),
                        req("name", "Name", Type.TEXT), pick("item_type", "Item type", LIBRARY_KINDS), pick("catalogue", "Catalogue", CATALOGUES),
                        fk("domain_persona_id", "Domain persona", "domain-persona", false),
                        fk("library_item_id", "Library item", "library-item", false),
                        pick("release", "Release", RELEASES), c("review", "Review", Type.TEXT),
                        c("visibility_scope", "Visibility", Type.TEXT), c("visibility_audience", "Audience", Type.TEXT),
                        fk("host_dept_bu_id", "Host Dept/BU", "dept-bu", false).after("company_user_id", "company_user_id"))));

        add(new Ent("catalogue-variant", "catalogue_variant", "variant_id", "Variant ID", "Catalogue variants", "Runs",
                List.of("name"), "item_id, seq",
                List.of(fk("item_id", "Catalogue item", "catalogue-item", true), req("name", "Name", Type.TEXT),
                        c("pricing_type", "Pricing type", Type.TEXT), c("tax_mode", "Tax", Type.TEXT),
                        c("hsn_sac", "HSN/SAC", Type.TEXT), c("promo", "Promo", Type.TEXT))));

        add(new Ent("catalogue-seat", "catalogue_seat", "catalogue_seat_id", "Seat ID", "Catalogue seats", "Runs",
                List.of("seat"), "item_id, seat",
                List.of(fk("item_id", "Catalogue item", "catalogue-item", true), c("seat", "Seat", Type.TEXT), c("side", "Side", Type.TEXT),
                        fk("dept_bu_id", "Dept/BU", "dept-bu", false), userOf("party_id", "Client or vendor", "Company", false),
                        fk("vendor_item_id", "Vendor's item", "catalogue-item", false))));

        add(new Ent("catalogue-item-krama", "catalogue_item_krama", "id", "ID", "Catalogue item Kramas", "Runs",
                List.of(), "item_id",
                List.of(fk("item_id", "Catalogue item", "catalogue-item", true), fk("krama_id", "Krama", "krama", true))));

        add(new Ent("run", "run", "run_id", "Run ID", "Runs", "Runs",
                List.of("instance_code"), "instance_code DESC",
                List.of(c("instance_code", "Instance ID", Type.TEXT), c("amendment_no", "Amendment", Type.INT),
                        fk("item_id", "Catalogue item", "catalogue-item", true), fk("krama_id", "Krama", "krama", true),
                        fk("company_user_id", "Entity", "users", true), fk("counterparty", "Counterparty", "users", false),
                        c("relationship", "Relationship", Type.TEXT),
                        fk("requestor_id", "Requestor/Conductor", "users", true), c("fy", "FY", Type.TEXT),
                        c("status", "Status", Type.TEXT), c("result", "Result", Type.TEXT),
                        c("locked_at", "Locked at", Type.TEXT), c("started_on", "Started on", Type.DATE))));

        add(new Ent("room", "room", "room_id", "Room ID", "Rooms (runs)", "Runs",
                List.of("name"), "kind",
                List.of(fk("run_id", "Run", "run", true), c("kind", "Kind", Type.TEXT), c("name", "Name", Type.TEXT))));

        add(new Ent("room-member", "room_member", "member_id", "Member ID", "Room members", "Runs",
                List.of(), "room_id",
                List.of(fk("room_id", "Room", "room", true), fk("person_id", "Person", "users", true), c("is_spoc", "SPOC", Type.BOOL))));

        add(new Ent("seat", "seat", "seat_id", "Seat ID", "Seats", "Runs",
                List.of("seat"), "seat",
                List.of(fk("run_id", "Run", "run", true), fk("stage_id", "Stage", "stage", true),
                        c("seat", "Seat", Type.TEXT), fk("person_id", "Person", "users", true))));

        add(new Ent("question-run", "question_run", "qr_id", "Question run ID", "Questions (runs)", "Runs",
                List.of("answer_state"), "due_date",
                List.of(fk("run_id", "Run", "run", true), fk("question_id", "Question", "question", true),
                        fk("room_id", "Room", "room", true), c("status", "Status", Type.TEXT), c("closed_as", "Closed as", Type.TEXT),
                        c("answer_state", "Answer", Type.TEXT), c("answer", "Answer text", Type.LONGTEXT),
                        c("source", "Source", Type.TEXT), c("due_date", "Due date", Type.DATE), c("reopen_count", "Reopened", Type.INT))));

        add(new Ent("answer-round", "answer_round", "round_id", "Round ID", "Answer rounds", "Runs",
                List.of("kind"), "at DESC",
                List.of(fk("qr_id", "Question run", "question-run", true), c("kind", "Kind", Type.TEXT),
                        c("body", "Answer", Type.LONGTEXT), c("reason", "Reason", Type.TEXT),
                        c("explanation", "Explanation", Type.LONGTEXT), fk("by_person", "By", "users", true), c("at", "At", Type.TEXT))));

        add(new Ent("audit-log", "audit_log", "audit_id", "Audit ID", "History and audit", "Runs",
                List.of("action"), "at DESC",
                List.of(c("at", "At", Type.TEXT), fk("run_id", "Run", "run", false), fk("krama_id", "Krama", "krama", false),
                        fk("actor", "Who", "users", false), c("action", "Action", Type.TEXT), c("detail", "Detail", Type.LONGTEXT))));
    }

    private Registry() {}

    public static Map<String, Ent> all() { return ENTITIES; }

    public static Ent get(String key) { return ENTITIES.get(key); }
}
