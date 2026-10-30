package com.compane.erdemo;

import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.util.Map;

import static com.compane.erdemo.CrudController.actor;
import static com.compane.erdemo.CrudController.bad;
import static com.compane.erdemo.CrudController.uuid;

/**
 * Krama actions (FRD v3.0). Every rule — who may design, seat, answer, review, agree, contest, deadlock,
 * cancel, reopen or amend, and what each person may see — is checked in the database functions in db/03_krama.sql.
 */
@RestController
@RequestMapping("/api")
public class RunController {

    private static final String ACTOR = "X-Acting-User";
    private final JdbcTemplate jdbc;
    // Settings come from the environment (compane-settings.env): sign-in codes by email, and whether Sample people show
    private final CodeMailer mailer = new CodeMailer(System.getenv("RESEND_API_KEY"), System.getenv("RESEND_FROM"));
    private final boolean demoPeople = !"false".equalsIgnoreCase(String.valueOf(System.getenv("SAMPLE_PEOPLE") != null ? System.getenv("SAMPLE_PEOPLE") : System.getenv("DEMO_PEOPLE")).trim());

    public RunController(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    // ---------- reading ----------

    @GetMapping(value = "/home", produces = MediaType.APPLICATION_JSON_VALUE)
    public String home(@RequestHeader(value = ACTOR, required = false) String a) {
        return jdbc.queryForObject("SELECT home_json(?::uuid)::text", String.class, actor(a));
    }

    @GetMapping(value = "/calendar", produces = MediaType.APPLICATION_JSON_VALUE)
    public String calendar(@RequestParam("from") String from, @RequestParam("to") String to,
                           @RequestHeader(value = ACTOR, required = false) String a) {
        return jdbc.queryForObject("SELECT calendar_json(?::uuid, ?::date, ?::date)::text", String.class,
                actor(a), isoDate(from, "From"), isoDate(to, "To"));
    }

    @GetMapping(value = "/runs", produces = MediaType.APPLICATION_JSON_VALUE)
    public String runs(@RequestHeader(value = ACTOR, required = false) String a) {
        return jdbc.queryForObject("SELECT runs_json(?::uuid)::text", String.class, actor(a));
    }

    @GetMapping(value = "/runs/{id}", produces = MediaType.APPLICATION_JSON_VALUE)
    public String run(@PathVariable String id, @RequestHeader(value = ACTOR, required = false) String a) {
        String json = jdbc.queryForObject("SELECT run_tree(?::uuid, ?::uuid)::text", String.class, uuid(id, "Run"), actor(a));
        if (json == null) throw new ResponseStatusException(HttpStatus.FORBIDDEN, "You are not seated in any room of this run");
        return json;
    }

    @GetMapping(value = "/runs/{id}/audit", produces = MediaType.APPLICATION_JSON_VALUE)
    public String audit(@PathVariable String id, @RequestHeader(value = ACTOR, required = false) String a) {
        String json = jdbc.queryForObject("SELECT audit_json(?::uuid, ?::uuid)::text", String.class, uuid(id, "Run"), actor(a));
        if (json == null) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "History and audit is for the Requestor/Conductor and the super-user");
        }
        return json;
    }

    @GetMapping(value = "/console", produces = MediaType.APPLICATION_JSON_VALUE)
    public String console(@RequestHeader(value = ACTOR, required = false) String a) {
        return jdbc.queryForObject("SELECT console_json(?::uuid)::text", String.class, actor(a));
    }

    @GetMapping(value = "/catalogue", produces = MediaType.APPLICATION_JSON_VALUE)
    public String catalogue(@RequestHeader(value = ACTOR, required = false) String a) {
        return jdbc.queryForObject("SELECT catalogue_json(?::uuid)::text", String.class, actor(a));
    }

    // ---------- screens shaped like the Figma ----------

    @GetMapping(value = "/business", produces = MediaType.APPLICATION_JSON_VALUE)
    public String business(@RequestHeader(value = ACTOR, required = false) String a) {
        return jdbc.queryForObject("SELECT business_json(?::uuid)::text", String.class, actor(a));
    }

    @GetMapping(value = "/entity/{id}/{view}", produces = MediaType.APPLICATION_JSON_VALUE)
    public String entityView(@PathVariable String id, @PathVariable String view,
                             @RequestHeader(value = ACTOR, required = false) String a) {
        String fn = switch (view) {
            case "home" -> "entity_home_json";
            case "tasks" -> "tasks_json";
            case "vendors" -> "vendors_json";
            case "catalogue" -> "entity_catalogue_json";
            default -> throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Unknown view");
        };
        return jdbc.queryForObject("SELECT " + fn + "(?::uuid, ?::uuid)::text", String.class, actor(a), uuid(id, "Entity"));
    }

    // ---------- Create: Krama lifecycle ----------

    @PostMapping("/krama/{id}/status")
    public Map<String, Object> status(@PathVariable String id, @RequestBody Map<String, Object> b,
                                      @RequestHeader(value = ACTOR, required = false) String a) {
        return call("SELECT set_krama_status(?::uuid, ?::uuid, ?)", uuid(id, "Krama"), actor(a), text(b, "status"));
    }

    @PostMapping("/krama/{id}/new-version")
    public Map<String, Object> newVersion(@PathVariable String id, @RequestBody Map<String, Object> b,
                                          @RequestHeader(value = ACTOR, required = false) String a) {
        String k = jdbc.queryForObject("SELECT new_version(?::uuid, ?::uuid, ?)::text", String.class,
                uuid(id, "Krama"), actor(a), text(b, "what_changed"));
        return Map.of("krama_id", k);
    }

    @PostMapping("/krama/{id}/import")
    public Map<String, Object> importKrama(@PathVariable String id, @RequestBody Map<String, Object> b,
                                           @RequestHeader(value = ACTOR, required = false) String a) {
        String k = jdbc.queryForObject("SELECT import_krama(?::uuid, ?::uuid, ?::uuid)::text", String.class,
                uuid(id, "Krama"), req(b, "entity_id", "Entity"), actor(a));
        return Map.of("krama_id", k);
    }

    // ---------- Connect and activate ----------

    @PostMapping("/catalogue/items")
    public Map<String, Object> addItem(@RequestBody Map<String, Object> b, @RequestHeader(value = ACTOR, required = false) String a) {
        String i = jdbc.queryForObject("SELECT add_catalogue_item(?::uuid, ?::uuid, ?::uuid, ?)::text", String.class,
                req(b, "krama_id", "Krama"), req(b, "entity_id", "Entity"), actor(a), text(b, "name"));
        return Map.of("item_id", i);
    }

    @PostMapping("/catalogue/{item}/activate")
    public Map<String, Object> activate(@PathVariable String item, @RequestBody Map<String, Object> b,
                                        @RequestHeader(value = ACTOR, required = false) String a) {
        String r = jdbc.queryForObject("SELECT activate(?::uuid, ?::uuid, ?::uuid, ?, ?::uuid)::text", String.class,
                uuid(item, "Catalogue item"), actor(a), opt(b, "counterparty", "Counterparty"),
                text(b, "relationship"), opt(b, "krama_id", "Krama"));
        return Map.of("run_id", r);
    }

    /** Which of the item's Kramas apply for this relationship and counterparty (the relationship matrix). */
    @GetMapping(value = "/catalogue/{item}/resolve", produces = MediaType.APPLICATION_JSON_VALUE)
    public String resolve(@PathVariable String item, @RequestParam("relationship") String relationship,
                          @RequestParam(value = "counterparty", required = false) String counterparty,
                          @RequestHeader(value = ACTOR, required = false) String a) {
        actor(a);
        return jdbc.queryForObject("SELECT resolve_json(?::uuid, ?, ?::uuid)::text", String.class, uuid(item, "Catalogue item"),
                relationship, counterparty == null || counterparty.isBlank() ? null : uuid(counterparty, "Counterparty"));
    }

    @PostMapping("/catalogue/{item}/assign")
    public Map<String, Object> assign(@PathVariable String item, @RequestBody Map<String, Object> b,
                                      @RequestHeader(value = ACTOR, required = false) String a) {
        return call("SELECT assign_krama(?::uuid, ?::uuid, ?::uuid)", uuid(item, "Catalogue item"), req(b, "krama_id", "Krama"), actor(a));
    }

    // ---------- Catalogue: Owned / Borrowed list, the item page and its sections ----------

    @PostMapping("/entity/{id}/catalogue")
    public Map<String, Object> createItem(@PathVariable String id, @RequestBody Map<String, Object> b,
                                          @RequestHeader(value = ACTOR, required = false) String a) {
        String i = jdbc.queryForObject("SELECT create_catalogue_item(?::uuid, ?::uuid, ?::jsonb)::text", String.class,
                uuid(id, "Entity"), actor(a), json(b));
        return Map.of("item_id", i);
    }

    @GetMapping(value = "/catalogue/{item}", produces = MediaType.APPLICATION_JSON_VALUE)
    public String item(@PathVariable String item, @RequestHeader(value = ACTOR, required = false) String a) {
        String j = jdbc.queryForObject("SELECT catalogue_item_json(?::uuid, ?::uuid)::text", String.class, actor(a), uuid(item, "Catalogue item"));
        if (j == null) throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Catalogue item not found");
        return j;
    }

    @PostMapping("/catalogue/{item}/sections/{section}")
    public Map<String, Object> saveSection(@PathVariable String item, @PathVariable String section, @RequestBody Map<String, Object> b,
                                           @RequestHeader(value = ACTOR, required = false) String a) {
        String id = jdbc.queryForObject("SELECT save_catalogue_section(?::uuid, ?::uuid, ?, ?::jsonb)::text", String.class,
                uuid(item, "Catalogue item"), actor(a), section, json(b));
        return id == null ? Map.of("ok", true) : Map.of("ok", true, "id", id);
    }

    // ---------- Conduct ----------

    @PostMapping("/runs/{id}/seats")
    public Map<String, Object> seat(@PathVariable String id, @RequestBody Map<String, Object> b,
                                    @RequestHeader(value = ACTOR, required = false) String a) {
        return call("SELECT seat_person(?::uuid, ?::uuid, ?, ?::uuid, ?::uuid)", uuid(id, "Run"),
                req(b, "stage_id", "Stage"), text(b, "seat"), req(b, "person_id", "Person"), actor(a));
    }

    @DeleteMapping("/seats/{id}")
    public Map<String, Object> unseat(@PathVariable String id, @RequestHeader(value = ACTOR, required = false) String a) {
        return call("SELECT unseat(?::uuid, ?::uuid)", uuid(id, "Seat"), actor(a));
    }

    @PostMapping("/questions/{id}/{action}")
    public Map<String, Object> answer(@PathVariable String id, @PathVariable String action,
                                      @RequestBody(required = false) Map<String, Object> body,
                                      @RequestHeader(value = ACTOR, required = false) String a) {
        Map<String, Object> b = body == null ? Map.of() : body;
        String qr = uuid(id, "Question");
        String who = actor(a);
        return switch (action) {
            case "submit" -> call("SELECT submit_answer(?::uuid, ?::uuid, ?, ?, ?::jsonb)", qr, who, text(b, "answer"), text(b, "source"),
                    json(b.get("data")));
            case "accept-removal" -> call("SELECT accept_removal(?::uuid, ?::uuid)", qr, who);
            case "third-party" -> call("SELECT third_party_request(?::uuid, ?::uuid, ?, ?)", qr, who, text(b, "party"), text(b, "email"));
            case "third-party-reply" -> call("SELECT third_party_reply(?::uuid, ?::uuid, ?)", qr, who, text(b, "reply"));
            case "call-in" -> call("SELECT call_in_split(?::uuid, ?::uuid, ?::uuid, string_to_array(?, E'\\n'), string_to_array(NULLIF(?, ''), ',')::int[])",
                    qr, who, req(b, "room_id", "Room"), text(b, "lines"), text(b, "discuss"));
            case "review" -> call("SELECT review_answer(?::uuid, ?::uuid)", qr, who);
            case "agree" -> call("SELECT agree_answer(?::uuid, ?::uuid)", qr, who);
            case "contest" -> call("SELECT contest_answer(?::uuid, ?::uuid, ?, ?)", qr, who, text(b, "reason"), text(b, "explanation"));
            case "deadlock" -> call("SELECT deadlock_answer(?::uuid, ?::uuid, ?)", qr, who, text(b, "explanation"));
            case "cancel" -> call("SELECT cancel_question(?::uuid, ?::uuid, ?)", qr, who, text(b, "explanation"));
            case "reopen" -> call("SELECT reopen_question(?::uuid, ?::uuid)", qr, who);
            case "quadrant" -> call("SELECT set_quadrant(?::uuid, ?::uuid, ?)", qr, who, text(b, "quadrant"));
            default -> throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Unknown action");
        };
    }

    // ---------- Standalone (one person; only the owner marks it Done) ----------

    @PostMapping("/standalone")
    public Map<String, Object> createStandalone(@RequestBody Map<String, Object> b,
                                                @RequestHeader(value = ACTOR, required = false) String a) {
        String t = jdbc.queryForObject("SELECT create_standalone(?::uuid, ?::uuid, ?, ?, ?::date, ?)::text", String.class,
                actor(a), req(b, "entity_id", "Entity"), text(b, "title"), text(b, "notes"), date(b, "due_date"), text(b, "quadrant"));
        return Map.of("task_id", t);
    }

    @PutMapping("/standalone/{id}")
    public Map<String, Object> updateStandalone(@PathVariable String id, @RequestBody Map<String, Object> b,
                                                @RequestHeader(value = ACTOR, required = false) String a) {
        return call("SELECT update_standalone(?::uuid, ?::uuid, ?, ?, ?::date, ?)", uuid(id, "Task"), actor(a),
                text(b, "title"), text(b, "notes"), date(b, "due_date"), text(b, "quadrant"));
    }

    @PostMapping("/standalone/{id}/done")
    public Map<String, Object> done(@PathVariable String id, @RequestHeader(value = ACTOR, required = false) String a) {
        return call("SELECT mark_done(?::uuid, ?::uuid)", uuid(id, "Task"), actor(a));
    }

    // ---------- Capabilities and default capabilities ----------

    @GetMapping(value = "/capabilities", produces = MediaType.APPLICATION_JSON_VALUE)
    public String capabilities() {
        return jdbc.queryForObject("SELECT capabilities_json()::text", String.class);
    }

    @PostMapping("/krama/{id}/capabilities")
    public Map<String, Object> addCapability(@PathVariable String id, @RequestBody Map<String, Object> b,
                                             @RequestHeader(value = ACTOR, required = false) String a) {
        return call("SELECT add_capability(?::uuid, ?::uuid, ?, ?::uuid, ?::uuid, ?::uuid, ?)", uuid(id, "Krama"), actor(a), text(b, "code"),
                opt(b, "stage_id", "Stage"), opt(b, "topic_id", "Topic"), opt(b, "question_id", "Question"), text(b, "note"));
    }

    @PostMapping("/capability-uses/{id}/remove")
    public Map<String, Object> removeCapability(@PathVariable String id, @RequestHeader(value = ACTOR, required = false) String a) {
        return call("SELECT remove_capability(?::uuid, ?::uuid)", uuid(id, "Capability"), actor(a));
    }

    @PostMapping("/split-lines/{id}/settle")
    public Map<String, Object> settleLine(@PathVariable String id, @RequestBody(required = false) Map<String, Object> body,
                                          @RequestHeader(value = ACTOR, required = false) String a) {
        Map<String, Object> b = body == null ? Map.of() : body;
        return call("SELECT settle_split_line(?::uuid, ?::uuid, ?)", uuid(id, "Line"), actor(a), text(b, "note"));
    }

    @PostMapping("/runs/{id}/estimates")
    public Map<String, Object> addEstimate(@PathVariable String id, @RequestBody Map<String, Object> b,
                                           @RequestHeader(value = ACTOR, required = false) String a) {
        return call("SELECT add_estimate_line(?::uuid, ?::uuid, ?, ?, ?::uuid, ?, ?::numeric, ?::numeric, ?::numeric)", uuid(id, "Run"), actor(a),
                text(b, "item"), text(b, "source"), opt(b, "vendor_id", "Vendor"), text(b, "vendor_name"), num(b, "est_cost"), num(b, "est_price"), num(b, "est_days"));
    }

    @PostMapping("/estimates/{id}/actuals")
    public Map<String, Object> actuals(@PathVariable String id, @RequestBody Map<String, Object> b,
                                       @RequestHeader(value = ACTOR, required = false) String a) {
        return call("SELECT set_actuals(?::uuid, ?::uuid, ?::numeric, ?::numeric, ?::numeric)", uuid(id, "Line"), actor(a),
                num(b, "act_cost"), num(b, "act_price"), num(b, "act_days"));
    }

    private static String num(Map<String, Object> b, String key) {
        Object v = b.get(key);
        if (v == null || v.toString().isBlank()) return null;
        try {
            new java.math.BigDecimal(v.toString().trim());
            return v.toString().trim();
        } catch (NumberFormatException e) {
            throw bad(key.replace('_', ' ') + " must be a number");
        }
    }

    // ---------- Rooms: more rooms, child rooms, topics per room, registries, chat ----------

    @GetMapping(value = "/rooms/{id}", produces = MediaType.APPLICATION_JSON_VALUE)
    public String room(@PathVariable String id, @RequestHeader(value = ACTOR, required = false) String a) {
        String json = jdbc.queryForObject("SELECT room_json(?::uuid, ?::uuid)::text", String.class, uuid(id, "Room"), actor(a));
        if (json == null) throw new ResponseStatusException(HttpStatus.FORBIDDEN, "You are not seated in this room");
        return json;
    }

    @PostMapping("/runs/{id}/rooms")
    public Map<String, Object> addRoom(@PathVariable String id, @RequestBody Map<String, Object> b,
                                       @RequestHeader(value = ACTOR, required = false) String a) {
        String r = jdbc.queryForObject("SELECT add_room(?::uuid, ?::uuid, ?, ?, ?::uuid, ?::uuid)::text", String.class,
                uuid(id, "Run"), actor(a), text(b, "kind"), text(b, "name"), opt(b, "with_entity", "Entity"), opt(b, "parent_room_id", "Room"));
        return Map.of("room_id", r);
    }

    @PostMapping("/rooms/{id}/{action}")
    public Map<String, Object> roomAction(@PathVariable String id, @PathVariable String action,
                                          @RequestBody(required = false) Map<String, Object> body,
                                          @RequestHeader(value = ACTOR, required = false) String a) {
        Map<String, Object> b = body == null ? Map.of() : body;
        String room = uuid(id, "Room");
        String who = actor(a);
        return switch (action) {
            case "grant" -> call("SELECT grant_room(?::uuid, ?::uuid)", room, who);
            case "members" -> call("SELECT add_room_member(?::uuid, ?::uuid, ?::uuid, ?)", room, req(b, "person_id", "Person"), who,
                    Boolean.TRUE.equals(b.get("spoc")));
            case "topics" -> call("SELECT set_room_topic(?::uuid, ?::uuid, ?, ?::uuid)", room, req(b, "topic_id", "Topic"),
                    Boolean.TRUE.equals(b.get("retain")), who);
            case "registries" -> call("SELECT add_registry(?::uuid, ?::uuid, ?, ?, ?)", room, who, text(b, "name"), text(b, "description"), text(b, "holds"));
            case "messages" -> call("SELECT post_message(?::uuid, ?::uuid, ?, ?::uuid)", room, who, text(b, "body"), opt(b, "mention_qr", "Question"));
            default -> throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Unknown action");
        };
    }

    @PostMapping("/registries/{id}/entries")
    public Map<String, Object> addEntry(@PathVariable String id, @RequestBody Map<String, Object> b,
                                        @RequestHeader(value = ACTOR, required = false) String a) {
        return call("SELECT add_registry_entry(?::uuid, ?::uuid, ?, ?, ?::date, ?::uuid, ?)", uuid(id, "Registry"), actor(a),
                text(b, "kind"), text(b, "title"), date(b, "on_date"), opt(b, "stage_id", "Stage"), text(b, "status"));
    }

    @PostMapping("/entries/{id}/status")
    public Map<String, Object> entryStatus(@PathVariable String id, @RequestBody Map<String, Object> b,
                                           @RequestHeader(value = ACTOR, required = false) String a) {
        return call("SELECT set_entry_status(?::uuid, ?::uuid, ?)", uuid(id, "Entry"), actor(a), text(b, "status"));
    }

    // ---------- Personal (Yousr) tasks ----------

    @GetMapping(value = "/personal/tasks", produces = MediaType.APPLICATION_JSON_VALUE)
    public String personalTasks(@RequestHeader(value = ACTOR, required = false) String a) {
        return jdbc.queryForObject("SELECT personal_tasks_json(?::uuid)::text", String.class, actor(a));
    }

    @PostMapping("/personal/tasks")
    public Map<String, Object> personalCreate(@RequestBody Map<String, Object> b, @RequestHeader(value = ACTOR, required = false) String a) {
        String t = jdbc.queryForObject("SELECT personal_task_act(NULL, ?::uuid, 'create', ?, ?::date, ?)::text", String.class,
                actor(a), text(b, "title"), date(b, "due_date"), text(b, "quadrant"));
        return Map.of("task_id", t);
    }

    @PostMapping("/personal/tasks/{id}/{action}")
    public Map<String, Object> personalAct(@PathVariable String id, @PathVariable String action,
                                           @RequestBody(required = false) Map<String, Object> body,
                                           @RequestHeader(value = ACTOR, required = false) String a) {
        Map<String, Object> b = body == null ? Map.of() : body;
        if (!java.util.List.of("done", "consent", "delete", "restore", "quadrant").contains(action)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Unknown action");
        }
        jdbc.queryForObject("SELECT personal_task_act(?::uuid, ?::uuid, ?, NULL, NULL, ?)::text", String.class,
                uuid(id, "Task"), actor(a), action, text(b, "quadrant"));
        return Map.of("ok", true);
    }

    // ---------- Conserve ----------

    @PostMapping("/runs/{id}/amend")
    public Map<String, Object> amend(@PathVariable String id, @RequestHeader(value = ACTOR, required = false) String a) {
        return call("SELECT amend_run(?::uuid, ?::uuid)", uuid(id, "Run"), actor(a));
    }

    // ---------- helpers ----------

    private Map<String, Object> call(String sql, Object... args) {
        jdbc.queryForList(sql, args);
        return Map.of("ok", true);
    }

    private static String req(Map<String, Object> b, String key, String label) {
        Object v = b.get(key);
        if (v == null || String.valueOf(v).isBlank()) throw bad(label + " is required");
        return uuid(v, label);
    }

    private static String opt(Map<String, Object> b, String key, String label) {
        Object v = b.get(key);
        return v == null || String.valueOf(v).isBlank() ? null : uuid(v, label);
    }

    private static String text(Map<String, Object> b, String key) {
        Object v = b.get(key);
        return v == null || String.valueOf(v).isBlank() ? null : String.valueOf(v);
    }

    // ---------- Platform actions: one doorway to the database's api_* functions ----------
    // Each api_<name>(actor, body) checks who may do what; sign-in calls run without an acting person.

    @PostMapping(value = "/do/{fn}", produces = MediaType.APPLICATION_JSON_VALUE)
    public String doFn(@PathVariable String fn, @RequestBody(required = false) Map<String, Object> body,
                       @RequestHeader(value = ACTOR, required = false) String a) {
        if (!fn.matches("[a-z_]{2,60}")) throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Unknown action");
        if (fn.equals("app_config")) {
            return "{\"demo_people\":" + demoPeople + ",\"codes_by_email\":" + mailer.enabled() + "}";
        }
        Boolean exists = jdbc.queryForObject("SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname = ?)", Boolean.class, "api_" + fn);
        if (!Boolean.TRUE.equals(exists)) throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Unknown action");
        String who = (a == null || a.isBlank()) ? null : uuid(a, "Working as");
        String out = jdbc.queryForObject("SELECT api_" + fn + "(?::uuid, ?::jsonb)::text", String.class, who, json(body));
        if (fn.equals("request_code") && mailer.enabled()) {
            // The code goes by email and never back to the screen
            Map<String, Object> b = body == null ? Map.of() : body;
            String purpose = text(b, "purpose");
            String to = "mobile".equals(purpose) ? text(b, "email") : text(b, "target");
            if (to == null || to.isBlank()) throw bad("Enter your email first; the mobile code comes there until SMS is connected");
            try {
                java.util.regex.Matcher m = java.util.regex.Pattern.compile("\"demo_code\"\\s*:\\s*\"(\\d+)\"").matcher(out);
                if (!m.find()) throw bad("The code could not be created. Try again.");
                String code = m.group(1);
                mailer.send(to.trim(), code, purpose == null ? "" : purpose);
            } catch (IllegalStateException e) {
                throw bad(e.getMessage());
            } catch (Exception e) {
                throw bad("The code could not be sent. Try again.");
            }
            return "{\"sent\":true,\"by_email\":true,\"to\":\"" + to.trim().replace("\\", "").replace("\"", "") + "\"}";
        }
        return out;
    }

    private static final com.fasterxml.jackson.databind.ObjectMapper MAPPER = new com.fasterxml.jackson.databind.ObjectMapper();

    /** The structured answer as JSON; an empty object when none was sent, so the answer is always checked. */
    private static String json(Object v) {
        try {
            return MAPPER.writeValueAsString(v == null ? Map.of() : v);
        } catch (Exception e) {
            throw bad("Could not read the answer");
        }
    }

    private static String date(Map<String, Object> b, String key) {
        String v = text(b, key);
        return v == null ? null : isoDate(v, "Due date");
    }

    private static String isoDate(String v, String label) {
        if (v == null || !v.trim().matches("\\d{4}-\\d{2}-\\d{2}")) throw bad(label + " must be a date (YYYY-MM-DD)");
        return v.trim();
    }
}
