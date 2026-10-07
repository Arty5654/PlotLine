package com.plotline.backend.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.function.Consumer;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.security.crypto.bcrypt.BCrypt;
import org.springframework.stereotype.Service;

import com.auth0.jwt.JWT;
import com.auth0.jwt.algorithms.Algorithm;
import com.auth0.jwt.exceptions.JWTVerificationException;
import com.auth0.jwt.interfaces.DecodedJWT;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.accounts.AccountDirectory;
import com.plotline.backend.dto.S3UserRecord;
import com.plotline.backend.util.LegalTerms;
import com.twilio.twiml.voice.Sms;
import io.github.cdimascio.dotenv.Dotenv;

import software.amazon.awssdk.core.ResponseBytes;
import software.amazon.awssdk.core.ResponseInputStream;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.model.S3Exception;
@Service
public class AuthService {
    private static final Logger log = LoggerFactory.getLogger(AuthService.class);


    private final S3Client s3Client;
    private final String bucketName = "plotline-database-bucket";
    private final ObjectMapper objectMapper;
    private final String jwt_secret;
    private final AccountDirectory accounts;

 
    
    private static final long jwt_expiry = 1000L * 60 * 60 * 24 * 30; // 1 month for new login (long math: the int version overflowed negative)

    private final SmsService smsService;
    @Autowired
    public AuthService(S3Client s3Client, SmsService smsService, AccountDirectory accounts) {
        this(s3Client, smsService, resolveEnv(Dotenv.configure().ignoreIfMissing().load(), "JWT_SECRET_KEY"), accounts);
    }

    // for tests: pass the jwt secret directly instead of reading it from the environment
    AuthService(S3Client s3Client, SmsService smsService, String jwtSecret, AccountDirectory accounts) {
        this.s3Client = s3Client;
        this.accounts = accounts;
        this.objectMapper = new ObjectMapper();
        this.smsService = smsService;
        this.jwt_secret = jwtSecret;
        if (jwt_secret == null || jwt_secret.isBlank()) {
            throw new IllegalStateException("JWT_SECRET_KEY is not configured.");
        }
    }

    private static String resolveEnv(Dotenv dotenv, String key) {
        String env = System.getenv(key);
        if (env != null && !env.isBlank()) {
            return env;
        }
        return dotenv.get(key);
    }

    // Usernames are public, searchable, and part of every storage path (users/<username>/...),
    // so they're limited to letters and numbers.
    public static final String USERNAME_RULES = "Usernames must be 3 to 30 letters or numbers.";
    private static final java.util.regex.Pattern USERNAME_PATTERN = java.util.regex.Pattern.compile("^[A-Za-z0-9]{3,30}$");

    public static boolean isValidUsername(String username) {
        return username != null && USERNAME_PATTERN.matcher(username).matches();
    }

    // Same password and email rules the app shows on sign-up (AuthViewModel.passwordRules / isValidEmail)
    public static final String PASSWORD_RULES =
            "Password needs 8+ characters with an uppercase letter, a lowercase letter, and a number.";
    public static final String EMAIL_RULES = "Enter a valid email address.";
    private static final java.util.regex.Pattern EMAIL_PATTERN =
            java.util.regex.Pattern.compile("^[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}$", java.util.regex.Pattern.CASE_INSENSITIVE);

    public static boolean isValidPassword(String password) {
        return password != null
                && password.length() >= 8
                && password.chars().anyMatch(Character::isUpperCase)
                && password.chars().anyMatch(Character::isLowerCase)
                && password.chars().anyMatch(Character::isDigit);
    }

    public static boolean isValidEmail(String email) {
        return email != null && EMAIL_PATTERN.matcher(email.trim()).matches();
    }

    // a valid, untaken username suggestion from an email: john.smith@gmail.com -> johnsmith (or johnsmith2...)
    public String suggestUsername(String email) {
        String local = email == null ? "" : email.split("@", 2)[0];
        String base = local.replaceAll("[^A-Za-z0-9]", "");
        if (base.isEmpty()) base = "user";
        if (base.length() > 30) base = base.substring(0, 30);
        while (base.length() < 3) base = base + "1";

        String candidate = base;
        for (int n = 2; userExists(candidate); n++) {
            String suffix = String.valueOf(n);
            candidate = base.substring(0, Math.min(base.length(), 30 - suffix.length())) + suffix;
        }
        return candidate;
    }

    // check if user exists for username uniqueness and login functions
    public boolean userExists(String username) {
        return userExistsAnyCase(username);
    }

    public boolean emailExists(String email) {
        return emailExistsAnyCase(email);
    }

    private boolean userExistsStrict(String username) {
        String key = userAccKey(username);
        try {
            s3Client.getObject(GetObjectRequest.builder().bucket(bucketName).key(key).build());
            return true;
        } catch (Exception e) {
            return false;
        }
    }
    
    private boolean userExistsAnyCase(String username) {
        String norm = normalizeUsername(username);
        if (userExistsStrict(norm)) return true;
        if (!norm.equals(username) && userExistsStrict(username)) return true;
        return false;
    }

    //returns TRUE if user is a google user
    public boolean googleUser(String username) {
        String norm = normalizeUsername(username);
        String key = userAccKey(norm);
        try {

            // Fetch user record from S3
            GetObjectRequest getRequest = GetObjectRequest.builder()
                    .bucket(bucketName)
                    .key(key)
                    .build();

            ResponseBytes<GetObjectResponse> objectBytes = s3Client.getObjectAsBytes(getRequest);
            String userJson = new String(objectBytes.asByteArray(), StandardCharsets.UTF_8);

            // Convert JSON to User Record
            S3UserRecord userRecord = objectMapper.readValue(userJson, S3UserRecord.class);

            return userRecord.getIsGoogle();

        } catch (Exception e) { /* fall through to legacy casing */ }

        if (!norm.equals(username)) {
            try {
                GetObjectRequest getRequest = GetObjectRequest.builder()
                        .bucket(bucketName)
                        .key(userAccKey(username))
                        .build();
                ResponseBytes<GetObjectResponse> objectBytes = s3Client.getObjectAsBytes(getRequest);
                String userJson = new String(objectBytes.asByteArray(), StandardCharsets.UTF_8);
                S3UserRecord userRecord = objectMapper.readValue(userJson, S3UserRecord.class);
                return userRecord.getIsGoogle();
            } catch (Exception ignored) { }
        }
        return false;
    }

    //returns TRUE if user was created through Sign in with Apple
    public boolean appleUser(String username) {
        S3UserRecord userRecord = readUserRecord(username);
        return userRecord != null && Boolean.TRUE.equals(userRecord.getIsApple());
    }

    //returns TRUE if the user hasn't accepted the current Terms of Service
    public boolean needsTerms(String username, String currentVersion) {
        S3UserRecord userRecord = readUserRecord(username);
        return userRecord != null && !currentVersion.equals(userRecord.getTermsVersion());
    }

    public boolean acceptTerms(String username, String version) {
        return updateUserRecord(username, record -> {
            record.setTermsVersion(version);
            record.setTermsAcceptedAt(System.currentTimeMillis());
        });
    }

    //returns TRUE if the user still has to verify a phone number. Only password accounts do:
    //Apple and Google have already verified the people who sign in with them
    public boolean needsPhoneVerification(String username) {
        S3UserRecord userRecord = readUserRecord(username);
        return userRecord != null && !skipsPhoneVerification(userRecord);
    }

    private static boolean skipsPhoneVerification(S3UserRecord userRecord) {
        return Boolean.TRUE.equals(userRecord.getIsVerified())
                || Boolean.TRUE.equals(userRecord.getIsGoogle())
                || Boolean.TRUE.equals(userRecord.getIsApple());
    }

    public S3UserRecord getUserRecord(String username) {
        return readUserRecord(username);
    }

    private S3UserRecord readUserRecord(String username) {
        try {
            GetObjectRequest getRequest = GetObjectRequest.builder()
                    .bucket(bucketName)
                    .key(userAccKey(normalizeUsername(username)))
                    .build();
            ResponseBytes<GetObjectResponse> objectBytes = s3Client.getObjectAsBytes(getRequest);
            return objectMapper.readValue(objectBytes.asByteArray(), S3UserRecord.class);
        } catch (Exception e) {
            return null;
        }
    }

    // read-modify-write a user's account record
    public boolean updateUserRecord(String username, Consumer<S3UserRecord> change) {
        S3UserRecord userRecord = readUserRecord(username);
        if (userRecord == null) return false;
        change.accept(userRecord);
        try {
            writeUserRecord(normalizeUsername(username), userRecord);
            return true;
        } catch (Exception e) {
            log.error("updateUserRecord failed", e);
            return false;
        }
    }

    private void writeUserRecord(String norm, S3UserRecord userRecord) throws Exception {
        PutObjectRequest putRequest = PutObjectRequest.builder()
                .bucket(bucketName)
                .key(userAccKey(norm))
                .contentType("application/json")
                .build();
        s3Client.putObject(putRequest, RequestBody.fromString(objectMapper.writeValueAsString(userRecord)));
        evictAccountCache(norm);
    }

    // Google/Apple accounts never sign in with a password, so they get one nobody knows
    private static String unusablePassword() {
        byte[] randomBytes = new byte[32];
        new SecureRandom().nextBytes(randomBytes);
        return Base64.getEncoder().encodeToString(randomBytes);
    }

    // create new user in s3 bucket
    public boolean createUser(String phone, String email, String username, String displayUsername, String rawPassword, Boolean isGoogle) {
        return createUser(phone, email, username, displayUsername, rawPassword, isGoogle, record -> { });
    }

    public boolean createGoogleUser(String email, String username, String displayUsername, String googleSub) {
        return createUser("", email, username, displayUsername, unusablePassword(), true,
                record -> record.setGoogleSub(googleSub));
    }

    public boolean createAppleUser(String email, String username, String displayUsername, String appleSub) {
        return createUser("", email, username, displayUsername, unusablePassword(), false, record -> {
            record.setIsApple(true);
            record.setAppleSub(appleSub);
        });
    }

    private boolean createUser(String phone, String email, String username, String displayUsername, String rawPassword,
                               Boolean isGoogle, Consumer<S3UserRecord> extraFields) {
        String norm = normalizeUsername(username);
        String normEmail = normalizeEmail(email);
        if (norm.isBlank() || normEmail.isBlank()) return false;
        if (!isValidUsername(norm) || (displayUsername != null && !isValidUsername(displayUsername.trim()))) return false;
        if (!isValidEmail(normEmail)) return false;

        if (userExistsAnyCase(norm)) return false;

        // the database reserves the username and email first, so two sign-ups at once can't both get them
        long createdAt = System.currentTimeMillis();
        if (!accounts.claim(norm, displayUsername, normEmail, createdAt)) return false;

        try {
            String hashedPassword = BCrypt.hashpw(rawPassword, BCrypt.gensalt());

            S3UserRecord userRecord = new S3UserRecord(norm, displayUsername, phone, normEmail, hashedPassword, isGoogle, false);
            userRecord.setCreatedAt(createdAt);
            extraFields.accept(userRecord);
            writeUserRecord(norm, userRecord);
            evictAccountCache(norm);

            return true;

        } catch (Exception e) {
            log.error("createUser failed", e);
            accounts.delete(norm); // free the name and email again
            return false;
        }
    }

    public String userLogin(String username, String rawPassword) {
        String norm = normalizeUsername(username);

        String keyToUse;
        if (userExists(norm)) {
            keyToUse = norm;
        } else if (userExists(username)) {
            keyToUse = username; // legacy casing
        } else {
            return "Given username does not exist";
        }

        try {
            // Fetch user record from S3
            GetObjectRequest getRequest = GetObjectRequest.builder()
                    .bucket(bucketName)
                    .key(userAccKey(keyToUse))
                    .build();

            ResponseBytes<GetObjectResponse> objectBytes = s3Client.getObjectAsBytes(getRequest);
            String userJson = new String(objectBytes.asByteArray(), StandardCharsets.UTF_8);

            // Convert JSON to User Record
            S3UserRecord userRecord = objectMapper.readValue(userJson, S3UserRecord.class);

            // Google/Apple accounts can't use the password form. Older Google accounts
            // stored the Google user id as their password, so never check it here.
            if (Boolean.TRUE.equals(userRecord.getIsGoogle())) {
                return "Please sign in with Google!";
            }
            if (Boolean.TRUE.equals(userRecord.getIsApple())) {
                return "Please sign in with Apple!";
            }

            // Verify Password
            if (rawPassword != null && BCrypt.checkpw(rawPassword, userRecord.getPassword())) {
                return verificationStatus(userRecord);
            }
            return "Incorrect Password";

        } catch (Exception e) {
            log.error("userLogin failed", e);
            return "Server Error";
        }
        
    }

    // sign a returning Google user back in, matching on their Google user id (never a password)
    public String googleLogin(String username, String googleSub) {
        S3UserRecord userRecord = readUserRecord(username);
        if (userRecord == null) {
            return "Given username does not exist";
        }
        if (!Boolean.TRUE.equals(userRecord.getIsGoogle())) {
            return "Non-Google account for this username exists";
        }
        if (googleSub == null || googleSub.isBlank()) {
            return "Google account does not match";
        }

        if (userRecord.getGoogleSub() != null) {
            if (!MessageDigest.isEqual(userRecord.getGoogleSub().getBytes(StandardCharsets.UTF_8),
                                       googleSub.getBytes(StandardCharsets.UTF_8))) {
                return "Google account does not match";
            }
            return verificationStatus(userRecord);
        }

        // legacy account: the Google id was stored as the password hash. Check it once,
        // then move it to googleSub and replace the password with an unusable one.
        if (!BCrypt.checkpw(googleSub, userRecord.getPassword())) {
            return "Google account does not match";
        }
        userRecord.setGoogleSub(googleSub);
        userRecord.setPassword(BCrypt.hashpw(unusablePassword(), BCrypt.gensalt()));
        try {
            writeUserRecord(normalizeUsername(username), userRecord);
        } catch (Exception e) {
            log.error("googleLogin failed", e); // still signed in; migration retries on the next Google sign-in
        }
        return verificationStatus(userRecord);
    }

    private static String verificationStatus(S3UserRecord userRecord) {
        return skipsPhoneVerification(userRecord) ? "true" : "Needs Verification";
    }

    // returns the username inside one of our login tokens, or null if it isn't valid
    public String usernameFromToken(String token) {
        DecodedJWT jwt = verifyToken(token);
        return jwt == null ? null : jwt.getClaim("username").asString();
    }

    // the user a request is signed in as: token must be valid, the account must still exist,
    // and the token can't predate the account (a deleted user's name taken by someone new)
    public String authenticatedUsername(String token) {
        DecodedJWT jwt = verifyToken(token);
        if (jwt == null || jwt.getIssuedAt() == null) return null;
        String username = normalizeUsername(jwt.getClaim("username").asString());
        if (username.isBlank()) return null;

        long createdAt = cachedAccount(username).createdAt();
        if (createdAt < 0) return null; // account no longer exists
        long issuedAtSeconds = jwt.getIssuedAtAsInstant().getEpochSecond();
        if (issuedAtSeconds < createdAt / 1000) return null;
        return username;
    }

    private DecodedJWT verifyToken(String token) {
        if (token == null || token.isBlank()) return null;
        try {
            return JWT.require(Algorithm.HMAC256(jwt_secret))
                    .withIssuer("PlotLineApp")
                    .build()
                    .verify(token);
        } catch (JWTVerificationException e) {
            return null;
        }
    }

    // The setup step a signed-in account still owes before it can use the app:
    // "Needs Terms" (accept the current terms) first, then "Needs Verification" (verify a phone,
    // password accounts only). null when the account is all set.
    public String pendingAccountStep(String username) {
        CachedAccount account = cachedAccount(normalizeUsername(username));
        if (account.createdAt() < 0) return null;
        if (!LegalTerms.CURRENT_VERSION.equals(account.termsVersion())) return NEEDS_TERMS;
        if (!account.skipsPhoneVerification()) return NEEDS_VERIFICATION;
        return null;
    }

    public static final String NEEDS_TERMS = "Needs Terms";
    public static final String NEEDS_VERIFICATION = "Needs Verification";

    // what the auth filter needs per account, cached briefly so every request doesn't read S3.
    // createdAt: -1 = no such account, 0 = older account without a recorded creation time
    private static final long ACCOUNT_CACHE_MILLIS = 60_000;
    private record CachedAccount(long createdAt, boolean skipsPhoneVerification, String termsVersion, long expiresAt) { }
    private final Map<String, CachedAccount> accountCache = new ConcurrentHashMap<>();

    private CachedAccount cachedAccount(String username) {
        long now = System.currentTimeMillis();
        CachedAccount cached = accountCache.get(username);
        if (cached != null && cached.expiresAt() > now) return cached;

        S3UserRecord userRecord = readUserRecord(username);
        CachedAccount account = userRecord == null
                ? new CachedAccount(-1, false, null, now + ACCOUNT_CACHE_MILLIS)
                : new CachedAccount(userRecord.getCreatedAt() == null ? 0 : userRecord.getCreatedAt(),
                        skipsPhoneVerification(userRecord), userRecord.getTermsVersion(), now + ACCOUNT_CACHE_MILLIS);
        accountCache.put(username, account);
        return account;
    }

    public void evictAccountCache(String username) {
        accountCache.remove(normalizeUsername(username));
    }

    public String changeUserPassword(String username, String oldPassword, String newPassword, String code) {
        if (!isValidPassword(newPassword)) {
            return PASSWORD_RULES;
        }
        String norm = normalizeUsername(username);
        String keyToUse;
        if (userExistsStrict(norm)) {
            keyToUse = norm;
        } else if (userExistsStrict(username)) {
            keyToUse = username;
        } else {
            return "User does not exist";
        }
    
        try {

            GetObjectRequest getRequest = GetObjectRequest.builder()
                .bucket(bucketName)
                .key(userAccKey(keyToUse))
                .build();
    
            ResponseBytes<GetObjectResponse> objectBytes = s3Client.getObjectAsBytes(getRequest);
            String userJson = new String(objectBytes.asByteArray(), StandardCharsets.UTF_8);

            S3UserRecord userRecord = objectMapper.readValue(userJson, S3UserRecord.class);

            if (Boolean.TRUE.equals(userRecord.getIsGoogle())) {
                return "This account signs in with Google and doesn't have a password.";
            }
            if (Boolean.TRUE.equals(userRecord.getIsApple())) {
                return "This account signs in with Apple and doesn't have a password.";
            }
    
            // if there is a otp code, verify it
            if (code != null && !code.isEmpty()) {
                log.debug("Entered code verification");
                boolean isCodeValid = smsService.verifyCode(userRecord.getPhone(), code, username);
                if (!isCodeValid) {
                    return "Invalid OTP Code";
                }
            } else {
                // no code = old and new password verification
                if (!BCrypt.checkpw(oldPassword, userRecord.getPassword())) {
                    return "Incorrect old password";
                }
            }
    
            String hashedNewPassword = BCrypt.hashpw(newPassword, BCrypt.gensalt());
            userRecord.setPassword(hashedNewPassword);
    
            String updatedUserJson = objectMapper.writeValueAsString(userRecord);
    
            // write back to the key we read from (not the raw username, which may differ in case)
            PutObjectRequest putRequest = PutObjectRequest.builder()
                .bucket(bucketName)
                .key(userAccKey(keyToUse))
                .contentType("application/json")
                .build();
    
            s3Client.putObject(putRequest, RequestBody.fromString(updatedUserJson));
            evictAccountCache(keyToUse); // a reset by SMS code also marks the phone verified
    
            return "success";
    
        } catch (Exception e) {
            log.error("changeUserPassword failed", e);
            return "Failed to update password";
        }
    }
    

    // generate jwt token for user on login/signup
    public String generateToken(String username) {

        long currentTime = System.currentTimeMillis();

        return JWT.create()
                .withIssuer("PlotLineApp")
                .withClaim("username", normalizeUsername(username))
                .withIssuedAt(new java.util.Date(currentTime))
                .withExpiresAt(new java.util.Date(currentTime + jwt_expiry))
                .sign(com.auth0.jwt.algorithms.Algorithm.HMAC256(jwt_secret));
    }


    // key for each bucket: username.json
    private String userAccKey(String username) {     
        return "users/" + username + "/account.json";
    }


    /** usernames containing the text, for friend search */
    public List<String> searchUsernames(String text, String excludeUsername) {
        return accounts.search(text, excludeUsername, 20);
    }

    /** 1 for the earliest account still around, 2 for the next, ... (null if unknown) */
    public Long signupRank(String username) {
        return accounts.signupRank(username);
    }

    public String normalizeUsername(String username) {
        return username == null ? "" : username.trim().toLowerCase();
    }

    // Get the original case-sensitive username from signup
    public String getDisplayUsername(String username) {
        String norm = normalizeUsername(username);
        String key = userAccKey(norm);
        try {
            GetObjectRequest getRequest = GetObjectRequest.builder()
                    .bucket(bucketName)
                    .key(key)
                    .build();

            ResponseBytes<GetObjectResponse> objectBytes = s3Client.getObjectAsBytes(getRequest);
            String userJson = new String(objectBytes.asByteArray(), StandardCharsets.UTF_8);

            S3UserRecord userRecord = objectMapper.readValue(userJson, S3UserRecord.class);

            // Return displayUsername if it exists, otherwise fall back to normalized username
            String display = userRecord.getDisplayUsername();
            return (display != null && !display.isBlank()) ? display : norm;
        } catch (Exception e) {
            return norm; // Fallback to normalized username
        }
    }

    public String normalizeEmail(String email) {
        return email == null ? "" : email.trim().toLowerCase();
    }

    private boolean emailExistsAnyCase(String email) {
        return accounts.emailTaken(email);
    }

    public String usernameForEmail(String email) {
        return accounts.usernameForEmail(email);
    }
  
}
