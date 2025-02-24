package com.plotline.backend.controller;

import com.google.api.client.googleapis.auth.oauth2.GoogleIdToken;
import com.google.api.client.googleapis.auth.oauth2.GoogleIdTokenVerifier;
import com.google.api.client.http.javanet.NetHttpTransport;
import com.google.api.client.json.JsonFactory;
import com.google.api.client.json.jackson2.JacksonFactory;

import com.plotline.backend.dto.AuthResponse;
import com.plotline.backend.dto.SignInRequest;
import com.plotline.backend.dto.SignUpRequest;
import com.plotline.backend.service.AuthService;

import io.github.cdimascio.dotenv.Dotenv;

import java.util.Arrays;
import java.util.Collections;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import com.plotline.backend.dto.GoogleSigninRequest;


@RestController
@RequestMapping("/auth")
public class AuthController {
    Dotenv dotenv = Dotenv.load();
    String googleClientId = dotenv.get("GOOGLE_CLIENT_ID");
    String googleIosClient = dotenv.get("GOOGLE_IOS_CLIENT_ID");

    @Autowired
    private final AuthService authService;
    public AuthController(AuthService authService) {
        this.authService = authService;
    }
 
    @PostMapping("/signup")
    public ResponseEntity<AuthResponse> signUp(@RequestBody SignUpRequest request) {

        // if user already exists, return error
        if (authService.userExists(request.getUsername())) {
            AuthResponse response = new AuthResponse(false, null, "User already exists");
            return ResponseEntity.ok(response);
        }
        
        // add user to db
        boolean created = authService.createUser(request.getPhone(), 
                                                 request.getUsername(), 
                                                 request.getPassword(),
                                                 false);
        if (!created) {
            return ResponseEntity.ok(new AuthResponse(false, null, "Could not create user"));
        }
        
        // create jwt token
        String token = authService.generateToken(request.getUsername());
        
        // signup successful
        return ResponseEntity.ok(new AuthResponse(true, token, "Needs Verification"));
    }

    @PostMapping("/signin")
    public ResponseEntity<AuthResponse> signIn(@RequestBody SignInRequest request) {

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

        if (loginResult.equals("Needs Verification")) {
            return ResponseEntity.ok(new AuthResponse(true, token, "Needs Verification"));
        }
        
        // signup successful
        return ResponseEntity.ok(new AuthResponse(true, token, null));
    }

    @PostMapping("/google-signin")
    public ResponseEntity<AuthResponse> googleSignIn(@RequestBody GoogleSigninRequest request) {

        String username = request.getUsername();
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

            String loginResult = "";

            if (!authService.userExists(username)) {

                // username does not exist, create new account for google user
                // using google token as password, encrypting for database
    
                boolean created = authService.createUser("", username, googleUserId, true);
                if (!created) {
                    return ResponseEntity.ok(new AuthResponse(false, null, "Could not create user"));
                }

                System.out.println("Google user CREATED");
    
                String token = authService.generateToken(username);
                return ResponseEntity.ok(new AuthResponse(true, token, "Needs Verification"));
    
            } else {
                // username exists already, try signing the google user back in
    
                // check if the existing user for this username is google
                // if not, append a few numbers to username to make it unique
                if (!authService.googleUser(username)) {
                    return ResponseEntity.ok(new AuthResponse(false, null, "Non-Google account for this username exists"));
    
                } else {
    
                    // log google user back into their account 
                    loginResult = authService.userLogin(username, googleUserId);
    
                    System.out.println("Google user LOGGED IN");
    
                    if (!loginResult.equals("true") && !loginResult.equals("Needs Verification")) {
                        return ResponseEntity.ok(new AuthResponse(false, null, loginResult));
                    }
    
                }
    
                String token = authService.generateToken(username);

                if (loginResult.equals("Needs Verification")) {
                    return ResponseEntity.ok(new AuthResponse(true, token, "Needs Verification"));
                }

                return ResponseEntity.ok(new AuthResponse(true, token, null));
    
            }
    
    
        } catch (Exception e) {
            e.printStackTrace();
            return ResponseEntity.ok(new AuthResponse(false, null, "Server Error"));

        }
    }
        
}
