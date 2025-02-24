package com.plotline.backend.service;

import java.nio.charset.StandardCharsets;

import org.springframework.security.crypto.bcrypt.BCrypt;
import org.springframework.stereotype.Service;

import com.auth0.jwt.JWT;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.dto.S3UserRecord;

import software.amazon.awssdk.core.ResponseBytes;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;

import io.github.cdimascio.dotenv.Dotenv;


@Service
public class AuthService {

    private final S3Client s3Client;
    private final String bucketName = "plotline-database-bucket";
    private final ObjectMapper objectMapper;
    Dotenv dotenv = Dotenv.load();
    private String jwt_secret = dotenv.get("JWT_SECRET_KEY");
    
    private static final long jwt_expiry = 1000 * 60 * 60 * 24 * 30; // 1 month for new login

    public AuthService(S3Client s3Client) {
        this.s3Client = s3Client;
        this.objectMapper = new ObjectMapper();
    }

    // check if user exists for username uniqueness and login functions
    public boolean userExists(String username) {
        String key = userAccKey(username);
        try {
            s3Client.getObject(GetObjectRequest.builder().bucket(bucketName).key(key).build());
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    //returns TRUE if user is a google user
    public boolean googleUser(String username) {
        String key = userAccKey(username);
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

        } catch (Exception e) {
            return false;
        }
    }

    // create new user in s3 bucket
    public boolean createUser(String phone, String username, String rawPassword, Boolean isGoogle) {

        if (userExists(username)) {
            return false;
        }

        try {
            

            String hashedPassword = BCrypt.hashpw(rawPassword, BCrypt.gensalt());

            S3UserRecord userRecord = new S3UserRecord(username, phone, hashedPassword, isGoogle, false);
            String userJson = objectMapper.writeValueAsString(userRecord);

            PutObjectRequest putRequest = PutObjectRequest.builder().
                                        bucket(bucketName).
                                        key(userAccKey(username)).
                                        contentType("application/json").
                                        build();

            s3Client.putObject(putRequest, RequestBody.fromString(userJson));

            return true;

        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }

    public String userLogin(String username, String rawPassword) {

        if (!userExists(username)) {
            return "Given username does not exist";
        }

        try {
            // Fetch user record from S3
            GetObjectRequest getRequest = GetObjectRequest.builder()
                    .bucket(bucketName)
                    .key(userAccKey(username))
                    .build();

            ResponseBytes<GetObjectResponse> objectBytes = s3Client.getObjectAsBytes(getRequest);
            String userJson = new String(objectBytes.asByteArray(), StandardCharsets.UTF_8);

            // Convert JSON to User Record
            S3UserRecord userRecord = objectMapper.readValue(userJson, S3UserRecord.class);

            // Verify Password
            if (BCrypt.checkpw(rawPassword, userRecord.getPassword())) {
                //correct password
                if (userRecord.getIsVerified()) {
                    return "true";
                } else {
                    return "Needs Verification";
                }
            } else {
                //incorrect password or google account

                if (googleUser(username)) {
                    return "Please sign in with Google!";
                }

                return "Incorrect Password"; 
            }

        } catch (Exception e) {
            e.printStackTrace();
            return "Server Error";
        }
        
    }

    // generate jwt token for user on login/signup
    public String generateToken(String username) {

        long currentTime = System.currentTimeMillis();

        return JWT.create()
                .withIssuer("PlotLineApp")
                .withClaim("username", username)
                .withIssuedAt(new java.util.Date(currentTime))
                .withExpiresAt(new java.util.Date(currentTime + jwt_expiry))
                .sign(com.auth0.jwt.algorithms.Algorithm.HMAC256(jwt_secret));
    }


    // key for each bucket: username.json
    private String userAccKey(String username) {     
        return "users/" + username + "/account.json";
    }
  
}
