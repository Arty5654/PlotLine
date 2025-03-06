package com.plotline.backend.service;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.locks.ReentrantLock;

import org.springframework.stereotype.Service;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.dto.EventDto;
import com.plotline.backend.dto.EventRequest;

import software.amazon.awssdk.core.ResponseBytes;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;

@Service
public class CalendarService {

    private final S3Client s3Client;
    private final ObjectMapper objectMapper;
    private final String bucketName = "plotline-database-bucket";
    private final ReentrantLock lock = new ReentrantLock();

    public CalendarService(S3Client s3Client) {
        this.s3Client = s3Client;
        this.objectMapper = new ObjectMapper();
    }

    // get all events for the user
    public List<EventDto> getEvents(String username) {
        try {
            String key = "users/" + username + "/calendar.json";

            GetObjectRequest getRequest = GetObjectRequest.builder()
                .bucket(bucketName)
                .key(key)
                .build();

            ResponseBytes<GetObjectResponse> objectBytes = s3Client.getObjectAsBytes(getRequest);
            String eventsJson = new String(objectBytes.asByteArray(), StandardCharsets.UTF_8);

            // parse json into eventDto
            List<EventDto> eventList = objectMapper.readValue(eventsJson, new TypeReference<List<EventDto>>() {});
            return eventList;
        } catch (Exception e) {
            // return empty if error
            return new ArrayList<>();
        }
    }

    // add new event

    public EventDto createEvent(EventDto newEvent, String username) throws Exception {
        lock.lock(); // Ensure no race conditions
        try {
            List<EventDto> existingEvents = getEvents(username);

            // if it is rent, subscription, or goal, avoid duplication
            if (!"user".equals(newEvent.getEventType())) {
                System.out.println("Type: " + newEvent.getEventType());
                newEvent = avoidDupe(newEvent, existingEvents, username, newEvent.getEventType());
                return newEvent;
            }

            existingEvents.add(newEvent);

            // write to s3
            saveEventsToS3(username, existingEvents);
            return newEvent;
        } finally {
            lock.unlock(); // Ensure lock is released
        }
}


    // update event linear traversal blah
    public EventDto updateEvent(EventDto updated, String username) throws Exception {
        List<EventDto> existingEvents = getEvents(username);

        for (int i = 0; i < existingEvents.size(); i++) {
            EventDto e = existingEvents.get(i);
            if (e.getId().equals(updated.getId())) {
                existingEvents.set(i, updated);
                saveEventsToS3(username, existingEvents);
                return updated;
            }
        }

        throw new Exception("Event not found for ID: " + updated.getId());
    }

    public void deleteEvent(String eventId, String username) throws Exception {
      List<EventDto> existing = getEvents(username);

      existing.removeIf(event -> event.getId().equals(eventId));
      saveEventsToS3(username, existing);
    }

    // write to s3 func
    private void saveEventsToS3(String username, List<EventDto> events) throws Exception {
        try {
            String key = "users/" + username + "/calendar.json";
            String eventsJson = objectMapper.writeValueAsString(events);
    
            //System.out.println("🔍 Preparing to save to S3: " + eventsJson);
    
            PutObjectRequest putRequest = PutObjectRequest.builder()
                    .bucket(bucketName)
                    .key(key)
                    .contentType("application/json")
                    .build();
    
            s3Client.putObject(putRequest, RequestBody.fromString(eventsJson));
            System.out.println("Successfully saved to S3 for user: " + username);
        } catch (Exception e) {
            System.err.println("Error saving to S3: " + e.getMessage());
            e.printStackTrace();
        }
    }
    

    private EventDto avoidDupe(EventDto newEvent, List<EventDto> existingEvents, String username, String type) {
        lock.lock(); // Ensure no race conditions
        try {
            EventDto existing = null;
    
            if (type.equals(newEvent.getEventType())) {
                // find existing event, if any
                for (EventDto e : existingEvents) {
                    if (type.equals(e.getEventType()) && e.getTitle().equals(newEvent.getTitle())) {
                        existing = e;
                        break;
                    }
                }
            }
    
            if (existing != null) {
                // if event exists, update it
                existing.setDescription(newEvent.getDescription());
                existing.setStartDate(newEvent.getStartDate());
                existing.setEndDate(newEvent.getEndDate());
    
                existingEvents.set(existingEvents.indexOf(existing), existing);
    
                saveEventsToS3(username, existingEvents);
                return existing;
            }
    
            // if event does not exist, create it
            existingEvents.add(newEvent);
    
            for (int i = 0; i < existingEvents.size(); i++) {
                System.out.println("Event " + i + ": " + existingEvents.get(i).getTitle());
            }
    
            saveEventsToS3(username, existingEvents);
        } catch (Exception e) {
            return new EventDto(); // return empty if error
        } finally {
            lock.unlock(); // Ensure lock is released
        }
    
        return newEvent;
    }
    


    public void deleteEventsByType(String username, String type) throws Exception {
      List<EventDto> existing = getEvents(username);

      existing.removeIf(event -> event.getEventType().equals(type));
      saveEventsToS3(username, existing);
    }
  
}

