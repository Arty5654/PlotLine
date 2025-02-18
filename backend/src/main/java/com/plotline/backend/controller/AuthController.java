package com.plotline.backend.controller;

import com.plotline.backend.dto.AuthResponse;
import com.plotline.backend.dto.SignInRequest;
import com.plotline.backend.dto.SignUpRequest;
import com.plotline.backend.service.AuthService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import com.plotline.backend.dto.GoogleSigninRequest;


@RestController
@RequestMapping("/auth")
public class AuthController {

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
        return ResponseEntity.ok(new AuthResponse(true, token, null));
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

        if (!loginResult.equals("true")) {
            return ResponseEntity.ok(new AuthResponse(false, null, loginResult));
        }
        
        // create jwt token
        String token = authService.generateToken(request.getUsername());
        
        // signup successful
        return ResponseEntity.ok(new AuthResponse(true, token, null));
    }

    @PostMapping("/google-signin")
    public ResponseEntity<AuthResponse> googleSignIn(@RequestBody GoogleSigninRequest request) {

        String username = request.getUsername();
        String tokenID = request.getIdToken();

        if (!authService.userExists(username)) {

            // username does not exist, create new account for google user
            // using google token as password, encrypting for database

            boolean created = authService.createUser("", username, tokenID, true);
            if (!created) {
                return ResponseEntity.ok(new AuthResponse(false, null, "Could not create user"));
            }

            System.out.println("Google user SIGNED UP");

        } else {
            // username exists already, try signing the google user back in

            // check if the existing user for this username is google
            // if not, append a few numbers to username to make it unique
            if (!authService.googleUser(username)) {
                return ResponseEntity.ok(new AuthResponse(false, null, "Non-Google account for this username exists"));

            } else {

                // log google user back into their account 
                String loginResult = authService.userLogin(username, tokenID);

                System.out.println("Google user LOGGED IN");

                if (!loginResult.equals("true")) {
                    return ResponseEntity.ok(new AuthResponse(false, null, loginResult));
                }

            }

        }

        String token = authService.generateToken(username);
        return ResponseEntity.ok(new AuthResponse(true, token, null));
    }
}
