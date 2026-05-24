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

import static com.plotline.backend.util.UsernameUtils.normalize;

@Service
public class CalendarService {

    private final S3Client s3Client;
    private final ObjectMapper objectMapper;
    private final String bucketName = "plotline-database-bucket";
    private final ReentrantLock lock = new ReentrantLock();
    private final UserProfileService userProfileService;
    private final CalendarAccessService calendarAccessService;

    public CalendarService(S3Client s3Client, UserProfileService userProfileService, CalendarAccessService calendarAccessService) {
        this.s3Client = s3Client;
        this.objectMapper = new ObjectMapper();
        this.userProfileService = userProfileService;
        this.calendarAccessService = calendarAccessService;
    }

    // get all events for the user
    public List<EventDto> getEvents(String username) {
        try {
            String key = "users/" + normalize(username) + "/calendar.json";

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
            String normUser = normalize(username);
            List<EventDto> existingEvents = getEvents(normUser);

            System.out.println(username + " is creating event: " + newEvent.getTitle());

            // if it is rent, subscription, or goal, avoid duplication
            if (!"user".equals(newEvent.getEventType())) {
                System.out.println("Type: " + newEvent.getEventType());
                newEvent = avoidDupe(newEvent, existingEvents, normUser, newEvent.getEventType());
                return newEvent;
            }

            // If a friend (addedBy) is creating on someone else's calendar, enforce approval
            String addedBy = newEvent.getAddedBy();
            if (addedBy != null && !addedBy.equalsIgnoreCase(normUser)) {
                boolean requiresApproval = calendarAccessService.requiresApproval(normUser, addedBy);
                newEvent.setStatus(requiresApproval ? "pending" : "approved");

                // Upsert by ID — prevents duplicates if published more than once
                for (int i = 0; i < existingEvents.size(); i++) {
                    if (existingEvents.get(i).getId().equals(newEvent.getId())) {
                        existingEvents.set(i, newEvent);
                        saveEventsToS3(normUser, existingEvents);
                        return newEvent;
                    }
                }
            }
            
            
            // Event planner (creating calendar events) Trophy
            userProfileService.incrementTrophy(normUser, "calendar-events-created", 1);

            // add to each friend's calendar as a pending invite
            if (newEvent.getInvitedFriends() != null && !newEvent.getInvitedFriends().isEmpty()) {
                for (String friend : newEvent.getInvitedFriends()) {
                    String normFriend = normalize(friend);
                    List<EventDto> friendEvents = getEvents(normFriend);

                    EventDto friendEvent = new EventDto(
                        newEvent.getId(),
                        newEvent.getTitle(),
                        newEvent.getDescription(),
                        newEvent.getStartDate(),
                        newEvent.getEndDate(),
                        newEvent.getEventType(),
                        newEvent.getRecurrence(),
                        new java.util.ArrayList<>(List.of(normUser))
                    );
                    friendEvent.setStatus("invite-pending");
                    friendEvent.setAddedBy(normUser);
                    friendEvent.setFriendsCanSee(newEvent.isFriendsCanSee());
                    friendEvents.add(friendEvent);
                    saveEventsToS3(normFriend, friendEvents);

                    // Track invite status on creator's event
                    newEvent.getInviteStatuses().put(normFriend, "pending");
                }

                newEvent.getInvitedFriends().add("c-123-creator-user-c-987");
                userProfileService.incrementTrophy(normUser, "friends-invited", newEvent.getInvitedFriends().size() - 1);
            }

            existingEvents.add(newEvent);
            // write to s3
            saveEventsToS3(normUser, existingEvents);

            return newEvent;
        } finally {
            lock.unlock(); // Ensure lock is released
        }
    }

    public EventDto updateEvent(EventDto updated, String username) throws Exception {
        String normUser = normalize(username);
        List<EventDto> existingEvents = getEvents(normUser);
        boolean found = false;
        EventDto previousVersion = null;

        for (int i = 0; i < existingEvents.size(); i++) {
            EventDto e = existingEvents.get(i);
            if (e.getId().equals(updated.getId())) {
                previousVersion = e;
                existingEvents.set(i, updated);
                found = true;
                break;
            }
        }

        if (!found) {
            throw new Exception("Event not found for ID: " + updated.getId());
        }

        saveEventsToS3(normUser, existingEvents);

        // Restore inviteStatuses from previousVersion — iOS client does not send them in update requests
        if (previousVersion != null
                && (updated.getInviteStatuses() == null || updated.getInviteStatuses().isEmpty())
                && previousVersion.getInviteStatuses() != null
                && !previousVersion.getInviteStatuses().isEmpty()) {
            updated.setInviteStatuses(new java.util.HashMap<>(previousVersion.getInviteStatuses()));
        }

        // Build set of new friends (normalized, excluding sentinel)
        java.util.Set<String> newFriendSet = new java.util.HashSet<>();
        if (updated.getInvitedFriends() != null) {
            for (String f : updated.getInvitedFriends()) {
                if (!f.contains("-creator-user-")) newFriendSet.add(normalize(f));
            }
        }

        // Build complete set of previously invited friends from BOTH invitedFriends and inviteStatuses
        java.util.Set<String> prevFriendSet = new java.util.HashSet<>();
        if (previousVersion != null) {
            if (previousVersion.getInvitedFriends() != null) {
                for (String f : previousVersion.getInvitedFriends()) {
                    if (!f.contains("-creator-user-")) prevFriendSet.add(normalize(f));
                }
            }
            if (previousVersion.getInviteStatuses() != null) {
                prevFriendSet.addAll(previousVersion.getInviteStatuses().keySet());
            }
        }

        // Remove event from friends who were uninvited
        for (String oldFriend : prevFriendSet) {
            if (!newFriendSet.contains(oldFriend)) {
                updated.getInviteStatuses().remove(oldFriend);
                List<EventDto> friendEvents = getEvents(oldFriend);
                friendEvents.removeIf(e -> e.getId().equals(updated.getId()));
                saveEventsToS3(oldFriend, friendEvents);
            }
        }

        // Update or create the event copy for each current invited friend
        for (String friend : newFriendSet) {
            List<EventDto> friendEvents = getEvents(friend);
            boolean eventExistsForFriend = false;

            for (int i = 0; i < friendEvents.size(); i++) {
                if (friendEvents.get(i).getId().equals(updated.getId())) {
                    EventDto updatedFriendEvent = new EventDto(
                        updated.getId(), updated.getTitle(), updated.getDescription(),
                        updated.getStartDate(), updated.getEndDate(),
                        updated.getEventType(), updated.getRecurrence(),
                        new java.util.ArrayList<>(List.of(normUser))
                    );
                    // Preserve the friend's current invite status
                    updatedFriendEvent.setStatus(friendEvents.get(i).getStatus());
                    updatedFriendEvent.setAddedBy(normUser);
                    updatedFriendEvent.setFriendsCanSee(updated.isFriendsCanSee());
                    friendEvents.set(i, updatedFriendEvent);
                    eventExistsForFriend = true;
                    break;
                }
            }

            if (!eventExistsForFriend) {
                // Newly invited friend — add as invite-pending
                EventDto newFriendEvent = new EventDto(
                    updated.getId(), updated.getTitle(), updated.getDescription(),
                    updated.getStartDate(), updated.getEndDate(),
                    updated.getEventType(), updated.getRecurrence(),
                    new java.util.ArrayList<>(List.of(normUser))
                );
                newFriendEvent.setStatus("invite-pending");
                newFriendEvent.setAddedBy(normUser);
                newFriendEvent.setFriendsCanSee(updated.isFriendsCanSee());
                friendEvents.add(newFriendEvent);
                updated.getInviteStatuses().put(friend, "pending");
            }

            saveEventsToS3(friend, friendEvents);
        }

        // Re-save creator event if inviteStatuses changed (new friends added)
        saveEventsToS3(normUser, existingEvents);

        return updated;
    }

    // Friend accepts or declines an event invite
    public boolean respondToEventInvite(String friendUsername, String eventId, boolean accept) throws Exception {
        String normFriend = normalize(friendUsername);
        lock.lock();
        try {
            // Update friend's copy of the event
            List<EventDto> friendEvents = getEvents(normFriend);
            EventDto friendEvent = null;
            for (EventDto e : friendEvents) {
                if (e.getId().equals(eventId) &&
                        ("invite-pending".equals(e.getStatus()) || "accepted".equals(e.getStatus()))) {
                    friendEvent = e;
                    break;
                }
            }
            if (friendEvent == null) return false;

            String creator = friendEvent.getAddedBy();
            if (creator == null && friendEvent.getInvitedFriends() != null && !friendEvent.getInvitedFriends().isEmpty()) {
                creator = normalize(friendEvent.getInvitedFriends().get(0));
            }

            if (accept) {
                friendEvent.setStatus("accepted");
            } else {
                // Decline: remove the event from friend's calendar entirely
                friendEvents.removeIf(e -> e.getId().equals(eventId));
            }
            saveEventsToS3(normFriend, friendEvents);

            // Update creator's inviteStatuses
            if (creator != null) {
                String normCreator = normalize(creator);
                List<EventDto> creatorEvents = getEvents(normCreator);
                for (EventDto e : creatorEvents) {
                    if (e.getId().equals(eventId)) {
                        e.getInviteStatuses().put(normFriend, accept ? "accepted" : "declined");
                        break;
                    }
                }
                saveEventsToS3(normCreator, creatorEvents);
            }

            return true;
        } finally {
            lock.unlock();
        }
    }

    public void deleteEvent(String eventId, String username) throws Exception {
        String normUser = normalize(username);
        List<EventDto> existing = getEvents(normUser);

        // get event to delete by id
        EventDto eventToDelete = null;
        for (EventDto event : existing) {
            if (event.getId().equals(eventId)) {
                eventToDelete = event;
                break;
            }
        }

        if (eventToDelete == null) {
            throw new Exception("Event not found for ID: " + eventId);
        }

        // Only cascade to friends if this is the creator's copy (addedBy is null on creator's copy)
        if (eventToDelete.getAddedBy() == null) {
            java.util.Set<String> friendsToClean = new java.util.HashSet<>();
            if (eventToDelete.getInviteStatuses() != null) {
                friendsToClean.addAll(eventToDelete.getInviteStatuses().keySet());
            }
            if (eventToDelete.getInvitedFriends() != null) {
                for (String f : eventToDelete.getInvitedFriends()) {
                    if (!f.contains("-creator-user-")) {
                        friendsToClean.add(normalize(f));
                    }
                }
            }
            for (String friend : friendsToClean) {
                List<EventDto> friendEvents = getEvents(friend);
                friendEvents.removeIf(event -> event.getId().equals(eventId));
                saveEventsToS3(friend, friendEvents);
            }
        }

        existing.removeIf(event -> event.getId().equals(eventId));
        saveEventsToS3(normUser, existing);
    }

    // write to s3 func
    private void saveEventsToS3(String username, List<EventDto> events) throws Exception {
        try {
            String key = "users/" + normalize(username) + "/calendar.json";
            String eventsJson = objectMapper.writeValueAsString(events);
    
            //System.out.println("Preparing to save to S3: " + eventsJson);
    
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
    


    // Replace all gcal_ events in one S3 read + write — used by Google Calendar batch sync
    public List<EventDto> batchSyncGcalEvents(String username, List<EventDto> incomingGcalEvents) throws Exception {
        String normUser = normalize(username);
        List<EventDto> existing = getEvents(normUser);

        // Keep all non-gcal events untouched
        List<EventDto> nonGcal = new java.util.ArrayList<>();
        for (EventDto e : existing) {
            if (!e.getId().startsWith("gcal_")) {
                nonGcal.add(e);
            }
        }

        // Merge: non-gcal events + fresh gcal events
        nonGcal.addAll(incomingGcalEvents);
        saveEventsToS3(normUser, nonGcal);
        return nonGcal;
    }

    public void deleteEventsByType(String username, String type) throws Exception {
      String normUser = normalize(username);
      List<EventDto> existing = getEvents(normUser);

      existing.removeIf(event -> event.getEventType().equals(type));
      saveEventsToS3(normUser, existing);
    }

    // Called when two users unfriend — cleans up event invites in both directions
    public void removeEventInvitesBetween(String userA, String userB) {
        try {
            String u1 = normalize(userA);
            String u2 = normalize(userB);
            cleanupEventsForUser(u1, u2);
            cleanupEventsForUser(u2, u1);
        } catch (Exception ignored) {}
    }

    // For `owner`: remove events invited by `exFriend`, and remove exFriend from invite tracking
    private void cleanupEventsForUser(String owner, String exFriend) throws Exception {
        List<EventDto> events = getEvents(owner);
        boolean changed = false;

        List<EventDto> toKeep = new java.util.ArrayList<>();
        for (EventDto event : events) {
            // Drop events that exFriend invited owner to
            String addedBy = event.getAddedBy() != null ? normalize(event.getAddedBy()) : "";
            if (exFriend.equals(addedBy)) {
                changed = true;
                continue;
            }

            // Remove exFriend from this user's own event invite tracking
            if (event.getInviteStatuses() != null && event.getInviteStatuses().containsKey(exFriend)) {
                event.getInviteStatuses().remove(exFriend);
                changed = true;
            }
            if (event.getInvitedFriends() != null) {
                boolean removed = event.getInvitedFriends().removeIf(f ->
                    !f.contains("-creator-user-") && exFriend.equals(normalize(f)));
                if (removed) changed = true;
            }

            toKeep.add(event);
        }

        if (changed) saveEventsToS3(owner, toKeep);
    }

}
