package com.plotline.backend.controller;

import com.google.api.client.googleapis.auth.oauth2.GoogleIdToken;
import com.google.api.client.googleapis.auth.oauth2.GoogleIdTokenVerifier;
import com.google.api.client.http.javanet.NetHttpTransport;
import com.google.api.client.json.JsonFactory;
import com.google.api.client.json.jackson2.JacksonFactory;

import com.plotline.backend.dto.AppleSigninRequest;
import com.plotline.backend.dto.AuthResponse;
import com.plotline.backend.dto.SignInRequest;
import com.plotline.backend.dto.SignUpRequest;
import com.plotline.backend.security.ActingUser;
import com.plotline.backend.security.CurrentUser;
import com.plotline.backend.service.AccountDeletionService;
import com.plotline.backend.service.AppleSignInService;
import com.plotline.backend.service.AuthService;
import io.github.cdimascio.dotenv.Dotenv;

import java.util.Arrays;
import java.util.List;
import java.util.Map;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import com.plotline.backend.dto.GoogleSigninRequest;


@RestController
@RequestMapping("/auth")
public class AuthController {
    Dotenv dotenv = Dotenv.configure().ignoreIfMissing().load();
    String googleClientId = dotenv.get("GOOGLE_CLIENT_ID");
    String googleIosClient = dotenv.get("GOOGLE_IOS_CLIENT_ID");

    @Autowired
    private final AuthService authService;
    private final AppleSignInService appleSignInService;
    private final AccountDeletionService accountDeletionService;
    public AuthController(AuthService authService, AppleSignInService appleSignInService,
                          AccountDeletionService accountDeletionService) {
        this.authService = authService;
        this.appleSignInService = appleSignInService;
        this.accountDeletionService = accountDeletionService;
    }
 
    @PostMapping("/signup")
    public ResponseEntity<AuthResponse> signUp(@RequestBody SignUpRequest request) {
        String displayUsername = request.getUsername().trim();
        String normalized = authService.normalizeUsername(request.getUsername());
        String normalizedEmail = authService.normalizeEmail(request.getEmail());
        if (normalized.isBlank()) {
            return ResponseEntity.ok(new AuthResponse(false, null, "Invalid username"));
        }
        if (normalizedEmail.isBlank()) {
            return ResponseEntity.ok(new AuthResponse(false, null, "Invalid email"));
        }
        if (!Boolean.TRUE.equals(request.getAcceptedTerms())) {
            return ResponseEntity.ok(new AuthResponse(false, null,
                    "Please confirm you're 18 or older and agree to the Terms of Service and Privacy Policy."));
        }
        request.setUsername(normalized);
        request.setEmail(normalizedEmail);

        // if user already exists, return error

        if (authService.googleUser(request.getUsername())) {
            return ResponseEntity.ok(new AuthResponse(false, null, "Google account for this username exists"));
        }

        if (authService.userExists(request.getUsername())) {
            AuthResponse response = new AuthResponse(false, null, "User already exists");
            return ResponseEntity.ok(response);
        }

        if (authService.emailExists(request.getEmail())) {
            AuthResponse response = new AuthResponse(false, null, "Email already exists");
            return ResponseEntity.ok(response);
        }

        // add user to db
        boolean created = authService.createUser(request.getPhone(),
                                                 request.getEmail(),
                                                 request.getUsername(),
                                                 displayUsername,
                                                 request.getPassword(),
                                                 false);
        if (!created) {
            return ResponseEntity.ok(new AuthResponse(false, null, "Could not create user"));
        }
        authService.acceptTerms(request.getUsername(), LegalController.TERMS_VERSION);
        
        // create jwt token
        String token = authService.generateToken(request.getUsername());

        // signup successful - return the original display username
        return ResponseEntity.ok(withTerms(new AuthResponse(true, token, "Needs Verification", displayUsername)));
    }

    @PostMapping("/signin")
    public ResponseEntity<AuthResponse> signIn(@RequestBody SignInRequest request) {
        String normalized = authService.normalizeUsername(request.getUsername());
        request.setUsername(normalized);

        // if user already exists, return error
        if (!authService.userExists(request.getUsername())) {
            AuthResponse response = new AuthResponse(false, null, "Username does not exist");
            return ResponseEntity.ok(response);
        }
        
        // add user to db
        String loginResult = authService.userLogin(request.getUsername(), request.getPassword());

        if (!loginResult.equals("true") && !loginResult.equals("Needs Verification")) {
            return ResponseEntity.ok(new AuthResponse(false, null, loginResult));
        }


        
        // create jwt token
        String token = authService.generateToken(request.getUsername());
        String displayUsername = authService.getDisplayUsername(request.getUsername());

        if (loginResult.equals("Needs Verification")) {
            return ResponseEntity.ok(withTerms(new AuthResponse(true, token, "Needs Verification", displayUsername)));
        }

        // signin successful
        return ResponseEntity.ok(withTerms(new AuthResponse(true, token, null, displayUsername)));
    }

    @PostMapping("/google-signin")
    public ResponseEntity<AuthResponse> googleSignIn(@RequestBody GoogleSigninRequest request) {

        String displayUsername = request.getUsername().trim();
        String username = authService.normalizeUsername(request.getUsername());
        String tokenID = request.getIdToken();

        try {

            // verify google id and extract the payload to store securely in db for re-signin

            JsonFactory jsonFactory = JacksonFactory.getDefaultInstance();
            GoogleIdTokenVerifier verifier = new GoogleIdTokenVerifier.Builder(new NetHttpTransport(), jsonFactory)
                    .setAudience(Arrays.asList(googleClientId, googleIosClient))
                    .setIssuer("https://accounts.google.com")
                    .build();
            GoogleIdToken idToken = verifier.verify(tokenID);


            if (idToken == null) {
                return ResponseEntity.ok(new AuthResponse(false, null, "Invalid Google ID Token"));
            }

            GoogleIdToken.Payload payload = idToken.getPayload();
            String googleUserId = payload.getSubject(); // Unique Google User ID
            String emailFromToken = payload.getEmail();
            String normalizedEmail = authService.normalizeEmail(emailFromToken);
            if (normalizedEmail == null || normalizedEmail.isBlank()) {
                return ResponseEntity.ok(new AuthResponse(false, null, "Email not available from Google"));
            }

            String loginResult = "";

            if (!authService.userExists(username)) {

                String owner = authService.usernameForEmail(normalizedEmail);
                if (owner != null && !owner.equals(username)) {
                    return ResponseEntity.ok(new AuthResponse(false, null, "Email already exists"));
                }

                // username does not exist, create new account for google user
                // (the Google user id is stored to recognize them later, never as a password)
    
                boolean created = authService.createGoogleUser(normalizedEmail, username, displayUsername, googleUserId);
                if (!created) {
                    return ResponseEntity.ok(new AuthResponse(false, null, "Could not create user"));
                }

                System.out.println("Google user CREATED");

                String token = authService.generateToken(username);
                return ResponseEntity.ok(withTerms(new AuthResponse(true, token, null, displayUsername)));
    
            } else {
                // username exists already, try signing the google user back in
                String owner = authService.usernameForEmail(normalizedEmail);
                if (owner != null && !owner.equals(username)) {
                    return ResponseEntity.ok(new AuthResponse(false, null, "Email already exists"));
                }
    
                // check if the existing user for this username is google
                // if not, append a few numbers to username to make it unique
                if (!authService.googleUser(username)) {
                    return ResponseEntity.ok(new AuthResponse(false, null, "Non-Google account for this username exists"));
    
                } else {
    
                    // log google user back into their account 
                    loginResult = authService.googleLogin(username, googleUserId);
    
                    System.out.println("Google user LOGGED IN");
    
                    if (!loginResult.equals("true") && !loginResult.equals("Needs Verification")) {
                        return ResponseEntity.ok(new AuthResponse(false, null, loginResult));
                    }
    
                }
    
                String token = authService.generateToken(username);
                String returnDisplayUsername = authService.getDisplayUsername(username);

                if (loginResult.equals("Needs Verification")) {
                    return ResponseEntity.ok(withTerms(new AuthResponse(true, token, "Needs Verification", returnDisplayUsername)));
                }

                return ResponseEntity.ok(withTerms(new AuthResponse(true, token, null, returnDisplayUsername)));
    
            }
    
    
        } catch (Exception e) {
            e.printStackTrace();
            return ResponseEntity.ok(new AuthResponse(false, null, "Server Error"));

        }
    }

    @PostMapping("/apple-signin")
    public ResponseEntity<AuthResponse> appleSignIn(@RequestBody AppleSigninRequest request) {
        return ResponseEntity.ok(withTerms(appleSignInService.signIn(request)));
    }

    // permanently delete the signed-in user's account. The account comes from the login
    // token (checked by JwtAuthFilter), never from the request body.
    @PostMapping("/delete-account")
    public ResponseEntity<AuthResponse> deleteAccount(@RequestBody(required = false) Map<String, String> request) {
        String appleCode = request != null ? request.get("appleAuthorizationCode") : null;
        return ResponseEntity.ok(accountDeletionService.deleteAccount(CurrentUser.require(), appleCode));
    }

    // swap a still-valid login token for a fresh one; the app calls this whenever it opens,
    // so people stay signed in as long as they use the app at least once every 30 days
    @PostMapping("/refresh")
    public ResponseEntity<AuthResponse> refresh() {
        String username = CurrentUser.require();
        String status = authService.needsPhoneVerification(username) ? "Needs Verification" : null;
        return ResponseEntity.ok(withTerms(new AuthResponse(true, authService.generateToken(username), status,
                authService.getDisplayUsername(username))));
    }

    // the signed-in user agrees to the current Terms of Service and Privacy Policy
    @PostMapping("/accept-terms")
    public ResponseEntity<AuthResponse> acceptTerms() {
        String username = CurrentUser.require();
        if (!authService.acceptTerms(username, LegalController.TERMS_VERSION)) {
            return ResponseEntity.ok(new AuthResponse(false, null, "Couldn't save your agreement. Please try again."));
        }
        AuthResponse response = new AuthResponse(true, null, null, authService.getDisplayUsername(username));
        response.setNeedsTerms(false);
        return ResponseEntity.ok(response);
    }

    // successful sign-ins say whether the user still has to accept the current terms
    private AuthResponse withTerms(AuthResponse response) {
        if (response.isSuccess() && response.getDisplayUsername() != null) {
            response.setNeedsTerms(authService.needsTerms(response.getDisplayUsername(), LegalController.TERMS_VERSION));
        }
        return response;
    }

    @PostMapping("/change-password")
    public ResponseEntity<AuthResponse> changePassword(@RequestBody Map<String, String> request) {
        String username = request.get("username");
        String oldPassword = request.get("oldPassword");
        String newPassword = request.get("newPassword");

        if (username == null || oldPassword == null || newPassword == null) {
            return ResponseEntity.badRequest().body(new AuthResponse(false, null, "Missing required fields"));
        }

        String result = authService.changeUserPassword(username, oldPassword, newPassword, "");

        if (result.equals("success")) {
            return ResponseEntity.ok(new AuthResponse(true, null, null));
        } else {
            return ResponseEntity.ok(new AuthResponse(false, null, result));
        }
    }

    @PostMapping("/change-password-code")
    public ResponseEntity<AuthResponse> changePasswordWithCode(@RequestBody Map<String, String> request) {
        String username = request.get("username");
        String newPassword = request.get("newPassword");
        String code = request.get("code");

        if (username == null || code == null || newPassword == null) {
            return ResponseEntity.badRequest().body(new AuthResponse(false, null, "Missing required fields"));
        }

        String result = authService.changeUserPassword(username, "", newPassword, code);

        if (result.equals("success")) {
            return ResponseEntity.ok(new AuthResponse(true, null, null));
        } else {
            return ResponseEntity.ok(new AuthResponse(false, null, result));
        }
    }

    @GetMapping("/user-exists")
    @ActingUser(value = {}, others = {"username"}) // looking up someone else, e.g. before a friend request
    public ResponseEntity<Boolean> userExists(@RequestParam String username) {
        if (authService.userExists(username)) {
            return ResponseEntity.ok(true);
        } else {
            return ResponseEntity.ok(false);
        }
    }

    @GetMapping("/get-users")
    public ResponseEntity<List<String>> fetchAllUsers() {
        try {
            List<String> users = authService.getAllUsernames();
            return ResponseEntity.ok(users);
        } catch (Exception e) {
            // log if desired
            return ResponseEntity
                .status(500)
                .body(List.of());
        }
    }

        
}
