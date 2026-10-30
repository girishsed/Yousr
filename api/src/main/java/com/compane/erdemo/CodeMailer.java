package com.compane.erdemo;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;

/**
 * Sends one-time codes by email through Resend (resend.com). With no key set, codes stay on screen (demo).
 * The key comes only from the environment (the .env file), never from code or the database.
 */
public class CodeMailer {
    private static final HttpClient HTTP = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build();
    private final String apiKey;
    private final String from;

    public CodeMailer(String apiKey, String from) {
        this.apiKey = apiKey == null ? "" : apiKey.trim();
        this.from = from == null ? "" : from.trim();
    }

    public boolean enabled() {
        return !apiKey.isEmpty() && !from.isEmpty();
    }

    public void send(String to, String code, String purpose) {
        String subject = "Your Yousr code: " + code;
        String what = switch (purpose) {
            case "signin" -> "to sign in";
            case "create_user_email" -> "to create your account";
            case "mobile" -> "to confirm your mobile (the SMS service is not connected yet, so it comes by email)";
            case "work_email" -> "to confirm the entity's work email";
            case "create_entity_personal" -> "to confirm your personal email for the new entity";
            case "join_work" -> "to join the entity with your work email";
            case "invite_sender" -> "to send an invite";
            case "connect_inviter" -> "to send a connection invite";
            case "connect_accept" -> "to accept a connection";
            case "business_model" -> "to change the Business Model";
            default -> "to continue";
        };
        String html = "<div style=\"font-family:Arial,sans-serif;font-size:15px;color:#1c1b1a\">"
                + "<p>Your one-time code " + esc(what) + " is</p>"
                + "<p style=\"font-size:28px;letter-spacing:6px;font-weight:bold\">" + esc(code) + "</p>"
                + "<p style=\"color:#75736f\">It works once. If you did not ask for it, ignore this email.</p></div>";
        String body = "{\"from\":" + q(from) + ",\"to\":[" + q(to) + "],\"subject\":" + q(subject) + ",\"html\":" + q(html) + "}";
        try {
            HttpRequest req = HttpRequest.newBuilder(URI.create("https://api.resend.com/emails"))
                    .timeout(Duration.ofSeconds(15))
                    .header("Authorization", "Bearer " + apiKey)
                    .header("Content-Type", "application/json")
                    .POST(HttpRequest.BodyPublishers.ofString(body)).build();
            HttpResponse<String> res = HTTP.send(req, HttpResponse.BodyHandlers.ofString());
            if (res.statusCode() >= 300) {
                throw new IllegalStateException("The email could not be sent (" + res.statusCode() + "). Check the Resend key and sender.");
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("The email could not be sent. Try again.");
        } catch (java.io.IOException e) {
            throw new IllegalStateException("The email could not be sent. Check the internet connection.");
        }
    }

    private static String esc(String s) {
        return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;");
    }

    private static String q(String s) {
        StringBuilder b = new StringBuilder("\"");
        for (char c : s.toCharArray()) {
            switch (c) {
                case '"' -> b.append("\\\"");
                case '\\' -> b.append("\\\\");
                case '\n' -> b.append("\\n");
                case '\r' -> b.append("\\r");
                default -> { if (c < 0x20) b.append(String.format("\\u%04x", (int) c)); else b.append(c); }
            }
        }
        return b.append('"').toString();
    }
}
