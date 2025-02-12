package com.plotline.backend.controller;

import com.plotline.backend.dto.AuthResponse;
import com.plotline.backend.dto.SignUpRequest;
import com.plotline.backend.service.AuthService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;


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
                                                 request.getPassword());
        if (!created) {
            return ResponseEntity.ok(new AuthResponse(false, null, "Could not create user"));
        }
        
        // create jwt token
        String token = authService.generateToken(request.getUsername());
        
        // signup successful
        return ResponseEntity.ok(new AuthResponse(true, token, null));
    }
    
}
