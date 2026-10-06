package com.plotline.backend.security;

import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

/**
 * Says which request fields identify the signed-in user on an endpoint.
 *
 * Every field named in {@link #value()} (path variable, query/form param, or top-level JSON body
 * property) must equal the signed-in user, or the request is rejected with 403.
 * Endpoints without this annotation use the default: "username" and "userId".
 *
 * {@link #others()} lists user fields that may name someone else (a friend, a list member...).
 * Those endpoints must check permission themselves; the guard test fails if a user-like field
 * is in neither list, so new endpoints can't skip this by accident.
 */
@Target(ElementType.METHOD)
@Retention(RetentionPolicy.RUNTIME)
public @interface ActingUser {
    String[] value() default {"username", "userId"};

    String[] others() default {};

    /** false when the JSON body's user fields describe something else (e.g. a shared list's owner) */
    boolean checkBody() default true;
}
