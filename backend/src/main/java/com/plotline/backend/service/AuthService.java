package com.plotline.backend.service;

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

    private final S3Client s3Client;
    private final String bucketName = "plotline-database-bucket";
    private final ObjectMapper objectMapper;
    private final String jwt_secret;
    private static final String EMAIL_INDEX_KEY = "email-index.json";

 
    
    private static final long jwt_expiry = 1000L * 60 * 60 * 24 * 30; // 1 month for new login (long math: the int version overflowed negative)

    private final SmsService smsService;
    @Autowired
    public AuthService(S3Client s3Client, SmsService smsService) {
        this(s3Client, smsService, resolveEnv(Dotenv.configure().ignoreIfMissing().load(), "JWT_SECRET_KEY"));
    }

    // for tests: pass the jwt secret directly instead of reading it from the environment
    AuthService(S3Client s3Client, SmsService smsService, String jwtSecret) {
        this.s3Client = s3Client;
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
            e.printStackTrace();
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

        if (userExistsAnyCase(norm)) return false;
        if (emailExistsAnyCase(normEmail)) return false;

        try {
            String hashedPassword = BCrypt.hashpw(rawPassword, BCrypt.gensalt());

            S3UserRecord userRecord = new S3UserRecord(norm, displayUsername, phone, normEmail, hashedPassword, isGoogle, false);
            userRecord.setCreatedAt(System.currentTimeMillis());
            extraFields.accept(userRecord);
            writeUserRecord(norm, userRecord);
            evictAccountCache(norm);

            updateAllUsersList(displayUsername);
            updateEmailIndex(normEmail, norm);

            return true;

        } catch (Exception e) {
            e.printStackTrace();
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
            e.printStackTrace();
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
            e.printStackTrace(); // still signed in; migration retries on the next Google sign-in
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
                System.out.println("Entered code verification");
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
            e.printStackTrace();
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

    private void updateAllUsersList(String username) throws Exception {
        final String allUsersKey = "all-users.json";
        List<String> allUsers;

        // try to read the existing list
        try {
            GetObjectRequest getListReq = GetObjectRequest.builder()
                .bucket(bucketName)
                .key(allUsersKey)
                .build();

            ResponseInputStream<GetObjectResponse> resp =
                s3Client.getObject(getListReq);

            allUsers = objectMapper.readValue(
                resp,
                new TypeReference<List<String>>() {}
            );

        } catch (S3Exception e) {
            // if it doesn't exist yet (404), start fresh
            if (e.statusCode() == 404) {
                allUsers = new ArrayList<>(Arrays.asList());
            } else {
                throw e;
            }
        }

        // append (with dedupe)
        boolean exists = allUsers.stream().anyMatch(u -> u.equalsIgnoreCase(username));
        if (!exists) {
            allUsers.add(username);
        }

        // write it back
        String allUsersJson = objectMapper.writeValueAsString(allUsers);
        PutObjectRequest putListReq = PutObjectRequest.builder()
            .bucket(bucketName)
            .key(allUsersKey)
            .contentType("application/json")
            .build();

        s3Client.putObject(
            putListReq,
            RequestBody.fromString(allUsersJson)
        );
    }

    public List<String> getAllUsernames() throws Exception {
        try {
            GetObjectRequest getReq = GetObjectRequest.builder()
                .bucket(bucketName)
                .key("all-users.json")
                .build();

            ResponseInputStream<GetObjectResponse> resp =
                s3Client.getObject(getReq);

            return objectMapper.readValue(
                resp,
                new TypeReference<List<String>>() {}
            );

        } catch (S3Exception e) {
            if (e.statusCode() == 404) {
                // no list yet => return empty
                return List.of();
            }
            throw e;
        }
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

    private Map<String, String> loadEmailIndex() throws Exception {
        try {
            GetObjectRequest getReq = GetObjectRequest.builder()
                .bucket(bucketName)
                .key(EMAIL_INDEX_KEY)
                .build();

            ResponseInputStream<GetObjectResponse> resp =
                s3Client.getObject(getReq);

            return objectMapper.readValue(
                resp,
                new TypeReference<Map<String, String>>() {}
            );
        } catch (S3Exception e) {
            if (e.statusCode() == 404) {
                return new java.util.HashMap<>();
            }
            throw e;
        }
    }

    private void saveEmailIndex(Map<String, String> map) throws Exception {
        String json = objectMapper.writeValueAsString(map);
        PutObjectRequest putReq = PutObjectRequest.builder()
            .bucket(bucketName)
            .key(EMAIL_INDEX_KEY)
            .contentType("application/json")
            .build();
        s3Client.putObject(putReq, RequestBody.fromString(json));
    }

    private boolean emailExistsAnyCase(String email) {
        String norm = normalizeEmail(email);
        if (norm.isBlank()) return false;
        try {
            Map<String, String> index = loadEmailIndex();
            return index.keySet().stream().anyMatch(e -> e.equalsIgnoreCase(norm));
        } catch (Exception e) {
            return false;
        }
    }

    private void updateEmailIndex(String email, String username) throws Exception {
        String normEmail = normalizeEmail(email);
        Map<String, String> index = loadEmailIndex();
        index.put(normEmail, username);
        saveEmailIndex(index);
    }

    public String usernameForEmail(String email) {
        String norm = normalizeEmail(email);
        if (norm.isBlank()) return null;
        try {
            Map<String, String> index = loadEmailIndex();
            for (var e : index.entrySet()) {
                if (e.getKey().equalsIgnoreCase(norm)) {
                    return e.getValue();
                }
            }
        } catch (Exception ignored) { }
        return null;
    }
  
}
