package com.compane.erdemo;

import com.compane.erdemo.Registry.Col;
import com.compane.erdemo.Registry.Ent;
import com.compane.erdemo.Registry.Type;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.dao.EmptyResultDataAccessException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.util.*;

/**
 * REST API for every table in the Registry:
 *   GET    /api/meta                 – tables, fields and links (used by the UI)
 *   GET    /api/{entity}             – list rows
 *   GET    /api/{entity}/{id}        – one row
 *   POST   /api/{entity}             – create a row
 *   PUT    /api/{entity}/{id}        – update a row
 *   DELETE /api/{entity}/{id}        – delete a row
 */
@RestController
@RequestMapping("/api")
public class CrudController {

    private final JdbcTemplate jdbc;
    private final ObjectMapper json = new ObjectMapper();

    public CrudController(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    // ---------- meta ----------

    @GetMapping("/meta")
    public Map<String, Object> meta() {
        List<Map<String, Object>> ents = new ArrayList<>();
        for (Ent e : Registry.all().values()) {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("key", e.key());
            m.put("pk", e.pk());
            m.put("pkLabel", e.pkLabel());
            m.put("label", e.label());
            m.put("group", e.group());
            m.put("display", e.display());
            m.put("cols", e.cols());
            m.put("readOnly", Registry.READ_ONLY.contains(e.key()));
            m.put("design", Registry.DESIGN.contains(e.key()));
            m.put("openToAll", Registry.OPEN_TO_ALL.contains(e.key()));
            ents.add(m);
        }
        return Map.of("statuses", Registry.STATUSES, "seats", Registry.SEATS, "reasons", Registry.REASONS,
                "sources", Registry.SOURCES, "entities", ents);
    }

    // ---------- who may write ----------

    /** Rule 20: only super-users change definitions. Work-flow tables change only through actions. */
    /**
     * Who may write: run tables never (actions only); Krama design rows by whoever may design that Krama
     * (platform super-user for platform Kramas, the entity super-user for the entity's own); masters by the super-user.
     */
    private void checkWrite(Ent e, String actorHeader, Map<String, Object> body, String id) {
        if (Registry.READ_ONLY.contains(e.key())) {
            throw bad(e.label() + " changes only through actions, not by direct edits");
        }
        String who = actor(actorHeader);
        if (Registry.DESIGN.contains(e.key())) {
            if (e.key().equals("krama") && id == null) {
                checkNewKrama(who, body);
                return;
            }
            String rowJson = id == null ? json(body)
                    : jdbc.queryForObject("SELECT row_to_json(t)::text FROM " + e.table() + " t WHERE " + e.pk() + " = ?::uuid",
                            String.class, uuid(id, e.pkLabel()));
            if (id != null && body != null && !e.key().equals("krama")) {
                // a row moved to another parent must be allowed there too
                Boolean okNew = jdbc.queryForObject("SELECT COALESCE(can_design(?::uuid, design_krama(?, ?::json)), true)",
                        Boolean.class, who, e.key(), json(body));
                if (!Boolean.TRUE.equals(okNew)) throw new ResponseStatusException(HttpStatus.FORBIDDEN, "You cannot change this Krama");
            }
            Boolean ok = jdbc.queryForObject("SELECT COALESCE(can_design(?::uuid, design_krama(?, ?::json)), false)",
                    Boolean.class, who, e.key(), rowJson);
            if (!Boolean.TRUE.equals(ok)) throw new ResponseStatusException(HttpStatus.FORBIDDEN, "You cannot change this Krama");
            return;
        }
        if (!isSuper(who)) throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Only the platform super-user can change masters");
    }

    /** A new Krama: platform super-user builds platform Kramas; an entity super-user builds Entity Built Entity Owned in its pool. */
    private void checkNewKrama(String who, Map<String, Object> body) {
        Object owner = body.get("owner_entity");
        body.remove("status");
        body.remove("version");
        body.remove("pool_mark");
        if (owner == null || String.valueOf(owner).isBlank()) {
            if (!isSuper(who)) throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Only the platform super-user builds platform Kramas");
            body.remove("owner_entity");
            return;
        }
        Boolean ok = jdbc.queryForObject("SELECT is_entity_super(?::uuid, ?::uuid)", Boolean.class, who, uuid(owner, "Owner entity"));
        if (!Boolean.TRUE.equals(ok)) throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Only that entity's super-user builds its Kramas");
        body.put("ownership_type", "Entity Built Entity Owned");
        body.put("pool_mark", "Entity Built");
    }

    private final com.fasterxml.jackson.databind.ObjectMapper mapper = new com.fasterxml.jackson.databind.ObjectMapper();

    private String json(Map<String, Object> body) {
        try {
            return mapper.writeValueAsString(body == null ? Map.of() : body);
        } catch (Exception ex) {
            throw bad("Could not read the request");
        }
    }

    /** The person the screens say we are working as (header X-Acting-User). */
    static String actor(String header) {
        if (header == null || header.isBlank()) throw bad("Choose who you are working as");
        return uuid(header, "Working as");
    }

    // ---------- read ----------

    /**
     * Rules 25/29: a super-user reads every table. Everyone else reads only Users and Expertise (for pickers);
     * they reach the catalogue, dashboard and work-flow through their own screens.
     */
    private String readFilter(Ent e, String actorHeader) {
        if (Registry.OPEN_TO_ALL.contains(e.key())) return "";
        String who = actor(actorHeader);
        if (isSuper(who)) return "";
        if (!Registry.OPEN_TO_ALL.contains(e.key())) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "You do not have access to " + e.label());
        }
        return "";
    }

    boolean isSuper(String who) {
        return Boolean.TRUE.equals(jdbc.queryForObject("SELECT is_super(?::uuid)", Boolean.class, who));
    }

    @GetMapping("/{entity}")
    public List<Map<String, Object>> list(@PathVariable String entity,
                                          @RequestHeader(value = "X-Acting-User", required = false) String actorHeader) {
        Ent e = ent(entity);
        String sql = "SELECT " + selectList(e) + " FROM " + e.table() + readFilter(e, actorHeader)
                + " ORDER BY " + e.orderBy();
        return jdbc.queryForList(sql).stream().map(r -> clean(e, r)).toList();
    }

    @GetMapping("/{entity}/{id}")
    public Map<String, Object> one(@PathVariable String entity, @PathVariable String id,
                                   @RequestHeader(value = "X-Acting-User", required = false) String actorHeader) {
        Ent e = ent(entity);
        String filter = readFilter(e, actorHeader);
        String sql = "SELECT " + selectList(e) + " FROM " + e.table()
                + (filter.isEmpty() ? " WHERE " : filter + " AND ") + e.pk() + " = ?::uuid";
        try {
            return clean(e, jdbc.queryForMap(sql, uuid(id, e.pkLabel())));
        } catch (EmptyResultDataAccessException ex) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, e.label() + " not found");
        }
    }

    /** Reads a row with no access check, for returning what was just written. */
    private Map<String, Object> fetch(String entity, String id) {
        Ent e = ent(entity);
        String sql = "SELECT " + selectList(e) + " FROM " + e.table() + " WHERE " + e.pk() + " = ?::uuid";
        return clean(e, jdbc.queryForMap(sql, uuid(id, e.pkLabel())));
    }

    // ---------- write ----------

    @PostMapping("/{entity}")
    @ResponseStatus(HttpStatus.CREATED)
    public Map<String, Object> create(@PathVariable String entity, @RequestBody Map<String, Object> body,
                                      @RequestHeader(value = "X-Acting-User", required = false) String actorHeader) {
        Ent e = ent(entity);
        checkWrite(e, actorHeader, body, null);
        List<String> names = new ArrayList<>();
        List<String> marks = new ArrayList<>();
        List<Object> args = new ArrayList<>();
        for (Col col : e.cols()) {
            if (col.expr() != null || col.virtual()) continue;   // worked out by the database, or only narrows a list
            Object v = convert(col, body.get(col.name()));
            if (v == null) {
                if (col.required()) throw bad(col.label() + " is required");
                continue; // let the database default apply
            }
            names.add(col.name());
            marks.add(mark(col));
            args.add(v);
        }
        String sql = names.isEmpty()
                ? "INSERT INTO " + e.table() + " DEFAULT VALUES RETURNING " + e.pk() + "::text"
                : "INSERT INTO " + e.table() + " (" + String.join(", ", names) + ") VALUES ("
                  + String.join(", ", marks) + ") RETURNING " + e.pk() + "::text";
        String id = jdbc.queryForObject(sql, String.class, args.toArray());
        return fetch(entity, id);
    }

    @PutMapping("/{entity}/{id}")
    public Map<String, Object> update(@PathVariable String entity, @PathVariable String id,
                                      @RequestBody Map<String, Object> body,
                                      @RequestHeader(value = "X-Acting-User", required = false) String actorHeader) {
        Ent e = ent(entity);
        if (e.key().equals("krama")) {
            for (String k : List.of("owner_entity", "ownership_type", "status", "version", "pool_mark")) body.remove(k);
        }
        checkWrite(e, actorHeader, body, id);
        List<String> sets = new ArrayList<>();
        List<Object> args = new ArrayList<>();
        for (Col col : e.cols()) {
            if (col.expr() != null || col.virtual() || !body.containsKey(col.name())) continue;
            Object v = convert(col, body.get(col.name()));
            if (v == null && col.required()) throw bad(col.label() + " is required");
            if (v == null && (col.type() == Type.UUIDS || col.type() == Type.ENUMS)) v = "{}";
            if (v == null && (col.type() == Type.BOOL)) v = Boolean.FALSE;
            if (v == null && (col.type() == Type.STATUS)) v = Registry.STATUSES.get(0);
            sets.add(col.name() + " = " + mark(col));
            args.add(v);
        }
        if (sets.isEmpty()) throw bad("Nothing to update");
        args.add(uuid(id, e.pkLabel()));
        int n = jdbc.update("UPDATE " + e.table() + " SET " + String.join(", ", sets)
                + " WHERE " + e.pk() + " = ?::uuid", args.toArray());
        if (n == 0) throw new ResponseStatusException(HttpStatus.NOT_FOUND, e.label() + " not found");
        return fetch(entity, id);
    }

    @DeleteMapping("/{entity}/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable String entity, @PathVariable String id,
                       @RequestHeader(value = "X-Acting-User", required = false) String actorHeader) {
        Ent e = ent(entity);
        checkWrite(e, actorHeader, null, id);
        int n = jdbc.update("DELETE FROM " + e.table() + " WHERE " + e.pk() + " = ?::uuid", uuid(id, e.pkLabel()));
        if (n == 0) throw new ResponseStatusException(HttpStatus.NOT_FOUND, e.label() + " not found");
    }

    // ---------- helpers ----------

    private Ent ent(String key) {
        Ent e = Registry.get(key);
        if (e == null) throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Unknown table: " + key);
        return e;
    }

    static ResponseStatusException bad(String msg) {
        return new ResponseStatusException(HttpStatus.BAD_REQUEST, msg);
    }

    private static String selectList(Ent e) {
        List<String> parts = new ArrayList<>();
        parts.add(e.pk() + "::text AS " + e.pk());
        for (Col col : e.cols()) {
            if (col.virtual()) continue;
            if (col.expr() != null) {
                parts.add(col.expr() + " AS " + col.name());
                continue;
            }
            parts.add(switch (col.type()) {
                case INT, BOOL -> col.name();
                case UUIDS, ENUMS -> "COALESCE(array_to_json(" + col.name() + ")::text, '[]') AS " + col.name();
                default -> col.name() + "::text AS " + col.name();
            });
        }
        return String.join(", ", parts);
    }

    private Map<String, Object> clean(Ent e, Map<String, Object> row) {
        Map<String, Object> out = new LinkedHashMap<>(row);
        for (Col col : e.cols()) {
            boolean isList = col.type() == Type.UUIDS || col.type() == Type.ENUMS;
            if (isList && out.get(col.name()) instanceof String s) {
                try {
                    out.put(col.name(), json.readValue(s, new TypeReference<List<String>>() {}));
                } catch (Exception ex) {
                    out.put(col.name(), List.of());
                }
            }
        }
        return out;
    }

    private static String mark(Col col) {
        return switch (col.type()) {
            case UUID -> "?::uuid";
            case DATE -> "?::date";
            case UUIDS -> "?::uuid[]";
            case ENUMS -> "?::text[]";
            default -> "?";
        };
    }

    static String uuid(Object v, String label) {
        try {
            return java.util.UUID.fromString(String.valueOf(v).trim()).toString();
        } catch (IllegalArgumentException ex) {
            throw bad(label + " is not a valid ID");
        }
    }

    /** Turns a JSON value into what the SQL placeholder expects; null means "no value". */
    private static Object convert(Col col, Object v) {
        if (v == null) return null;
        if (v instanceof String s && s.isBlank() && col.type() != Type.UUIDS && col.type() != Type.ENUMS) return null;
        switch (col.type()) {
            case UUID:
                return uuid(v, col.label());
            case DATE:
                String d = String.valueOf(v).trim();
                if (!d.matches("\\d{4}-\\d{2}-\\d{2}")) throw bad(col.label() + " must be a date (YYYY-MM-DD)");
                return d;
            case INT:
                try {
                    return v instanceof Number n ? n.intValue() : Integer.parseInt(String.valueOf(v).trim());
                } catch (NumberFormatException ex) {
                    throw bad(col.label() + " must be a whole number");
                }
            case BOOL:
                return v instanceof Boolean b ? b : Boolean.parseBoolean(String.valueOf(v));
            case STATUS:
                String st = String.valueOf(v);
                if (!Registry.STATUSES.contains(st)) throw bad("Status must be one of " + Registry.STATUSES);
                return st;
            case UUIDS:
                if (!(v instanceof List<?> list)) throw bad(col.label() + " must be a list of IDs");
                List<String> ids = new ArrayList<>();
                for (Object o : list) ids.add(uuid(o, col.label()));
                return "{" + String.join(",", new LinkedHashSet<>(ids)) + "}";
            case ENUM:
                String one = String.valueOf(v);
                if (!col.options().contains(one)) throw bad(col.label() + " must be one of " + col.options());
                return one;
            case ENUMS:
                if (!(v instanceof List<?> picked)) throw bad(col.label() + " must be a list");
                List<String> quoted = new ArrayList<>();
                for (Object o : new LinkedHashSet<>(picked)) {
                    String val = String.valueOf(o);
                    if (!col.options().contains(val)) throw bad(col.label() + " must be from " + col.options());
                    quoted.add("\"" + val.replace("\\", "\\\\").replace("\"", "\\\"") + "\"");
                }
                return "{" + String.join(",", quoted) + "}";
            default:
                return String.valueOf(v);
        }
    }
}
