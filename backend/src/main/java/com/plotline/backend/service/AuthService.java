package com.plotline.backend.service;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.security.crypto.bcrypt.BCrypt;
import org.springframework.stereotype.Service;

import com.auth0.jwt.JWT;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.dto.S3UserRecord;
import com.twilio.twiml.voice.Sms;

import software.amazon.awssdk.core.ResponseBytes;
import software.amazon.awssdk.core.ResponseInputStream;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.model.S3Exception;
import io.github.cdimascio.dotenv.Dotenv;


@Service
public class AuthService {

    private final S3Client s3Client;
    private final String bucketName = "plotline-database-bucket";
    private final ObjectMapper objectMapper;
    Dotenv dotenv = Dotenv.load();
    private String jwt_secret = dotenv.get("JWT_SECRET_KEY");

 
    
    private static final long jwt_expiry = 1000 * 60 * 60 * 24 * 30; // 1 month for new login

    private final SmsService smsService;
    public AuthService(S3Client s3Client, SmsService smsService) {
        this.s3Client = s3Client;
        this.objectMapper = new ObjectMapper();
        this.smsService = smsService;
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

            updateAllUsersList(username);

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

    public String changeUserPassword(String username, String oldPassword, String newPassword, String code) {
        if (!userExists(username)) {
            return "User does not exist";
        }
    
        try {

            GetObjectRequest getRequest = GetObjectRequest.builder()
                .bucket(bucketName)
                .key(userAccKey(username))
                .build();
    
            ResponseBytes<GetObjectResponse> objectBytes = s3Client.getObjectAsBytes(getRequest);
            String userJson = new String(objectBytes.asByteArray(), StandardCharsets.UTF_8);

            S3UserRecord userRecord = objectMapper.readValue(userJson, S3UserRecord.class);
    
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
    
            PutObjectRequest putRequest = PutObjectRequest.builder()
                .bucket(bucketName)
                .key(userAccKey(username))
                .build();
    
            s3Client.putObject(putRequest, RequestBody.fromString(updatedUserJson));
    
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
                .withClaim("username", username)
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
        if (!allUsers.contains(username)) {
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
  
}
