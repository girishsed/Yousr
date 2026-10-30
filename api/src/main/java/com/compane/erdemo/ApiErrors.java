package com.compane.erdemo;

import org.springframework.dao.DataAccessException;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.server.ResponseStatusException;

import java.util.Map;

/** Turns database and rule errors into a short {"message": "..."} the screens can show. */
@RestControllerAdvice
public class ApiErrors {

    @ExceptionHandler(DataAccessException.class)
    public ResponseEntity<Map<String, String>> dbError(DataAccessException ex) {
        String msg = ex.getMostSpecificCause().getMessage();
        if (msg != null) {
            int i = msg.indexOf("\n");
            if (i > 0) msg = msg.substring(0, i);
            msg = msg.replaceFirst("^ERROR: ", "");
        }
        return ResponseEntity.badRequest().body(Map.of("message", msg == null ? "Database error" : msg));
    }

    @ExceptionHandler(ResponseStatusException.class)
    public ResponseEntity<Map<String, String>> statusError(ResponseStatusException ex) {
        return ResponseEntity.status(ex.getStatusCode())
                .body(Map.of("message", ex.getReason() == null ? "Error" : ex.getReason()));
    }
}
