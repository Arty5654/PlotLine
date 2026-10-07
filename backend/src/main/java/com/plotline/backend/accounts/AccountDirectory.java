package com.plotline.backend.accounts;

import java.util.List;

import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import static com.plotline.backend.util.UsernameUtils.normalize;

/**
 * Every account's username and email (Postgres "accounts" table). Replaces all-users.json and
 * email-index.json: the database keeps usernames and emails unique, even when two people sign
 * up at the same moment. The rest of each account still lives in users/{username}/account.json.
 */
@Repository
public class AccountDirectory {

    private final JdbcTemplate jdbc;

    public AccountDirectory(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    /** reserves the username and email for a new account; false if either is already taken */
    public boolean claim(String username, String displayUsername, String email, long createdAtMillis) {
        try {
            jdbc.update("""
                    insert into accounts (username, display_username, email, created_at)
                    values (?, ?, ?, to_timestamp(? / 1000.0))
                    """, normalize(username), displayName(username, displayUsername), normalizeEmail(email), createdAtMillis);
            return true;
        } catch (DuplicateKeyException e) {
            return false;
        }
    }

    public void delete(String username) {
        jdbc.update("delete from accounts where username = ?", normalize(username));
    }

    public boolean emailTaken(String email) {
        return usernameForEmail(email) != null;
    }

    /** the account using this email, or null */
    public String usernameForEmail(String email) {
        String normalized = normalizeEmail(email);
        if (normalized == null) return null;
        List<String> owners = jdbc.queryForList("select username from accounts where email = ?", String.class, normalized);
        return owners.isEmpty() ? null : owners.get(0);
    }

    /** 1 for the earliest account still around, 2 for the next, ...; null if there's no such account */
    public Long signupRank(String username) {
        List<Long> rank = jdbc.queryForList("""
                select (select count(*) from accounts earlier where earlier.signup_number <= a.signup_number)
                from accounts a where a.username = ?
                """, Long.class, normalize(username));
        return rank.isEmpty() ? null : rank.get(0);
    }

    /**
     * Usernames containing the text (letters and numbers only), names that start with it first.
     * Display spelling, without the person searching.
     */
    public List<String> search(String text, String excludeUsername, int limit) {
        String query = text == null ? "" : text.replaceAll("[^A-Za-z0-9]", "").toLowerCase();
        if (query.isEmpty()) return List.of();
        return jdbc.queryForList("""
                select display_username from accounts
                where username like ? and username <> ?
                order by (username like ?) desc, username
                limit ?
                """, String.class, "%" + query + "%", normalize(excludeUsername), query + "%", limit);
    }

    private static String displayName(String username, String displayUsername) {
        return displayUsername != null && !displayUsername.isBlank() ? displayUsername.trim() : normalize(username);
    }

    private static String normalizeEmail(String email) {
        if (email == null || email.isBlank()) return null;
        return email.trim().toLowerCase();
    }
}
