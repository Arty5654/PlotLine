package com.plotline.backend.util;

public final class UsernameUtils {
    private UsernameUtils() {}

    public static String normalize(String username) {
        return username == null ? "" : username.trim().toLowerCase();
    }
}
