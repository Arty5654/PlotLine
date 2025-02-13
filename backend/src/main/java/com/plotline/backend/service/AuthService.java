package com.plotline.backend.service;

import org.springframework.security.crypto.bcrypt.BCrypt;
import org.springframework.stereotype.Service;

import com.auth0.jwt.JWT;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.dto.S3UserRecord;

import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;


@Service
public class AuthService {

    private final S3Client s3Client;
    private final String bucketName = "plotline-accounts";
    private final ObjectMapper objectMapper;

    private static final String jwt_secret = System.getenv("JWT_SECRET");
    private static final long jwt_expiry = 1000 * 60 * 60 * 24 * 30; // 1 month for new login

    public AuthService(S3Client s3Client) {
        this.s3Client = s3Client;
        this.objectMapper = new ObjectMapper();
    }

    // check if user exists for username uniqueness and login functions
    public boolean userExists(String username) {
        String key = userKey(username);
        try {
            s3Client.getObject(GetObjectRequest.builder().bucket(bucketName).key(key).build());
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    // create new user in s3 bucket
    public boolean createUser(String phone, String username, String rawPassword) {

        if (userExists(username)) {
            return false;
        }

        try {

            String hashedPassword = BCrypt.hashpw(rawPassword, BCrypt.gensalt());

            S3UserRecord userRecord = new S3UserRecord(phone, username, hashedPassword);
            String userJson = objectMapper.writeValueAsString(userRecord);

            PutObjectRequest putRequest = PutObjectRequest.builder().
                                        bucket(bucketName).
                                        key(userKey(username)).
                                        contentType("application/json").
                                        build();

            s3Client.putObject(putRequest, RequestBody.fromString(userJson));

            return true;

        } catch (Exception e) {
            e.printStackTrace();
            return false;
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
    private String userKey(String username) {     
        return username + ".json";
    }
  
}
