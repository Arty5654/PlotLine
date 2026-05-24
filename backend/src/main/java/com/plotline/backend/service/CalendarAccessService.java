package com.plotline.backend.service;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.dto.*;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.core.ResponseBytes;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.*;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.time.ZoneOffset;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import java.util.*;
import java.util.concurrent.locks.ReentrantLock;
import java.util.stream.Collectors;

import static com.plotline.backend.util.UsernameUtils.normalize;

@Service
public class CalendarAccessService {

    private final S3Client s3Client;
    private final ObjectMapper objectMapper;
    private final String bucketName = "plotline-database-bucket";
    private final ReentrantLock lock = new ReentrantLock();
    private static final DateTimeFormatter FORMATTER =
        DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ssXXX");

    public CalendarAccessService(S3Client s3Client) {
        this.s3Client = s3Client;
        this.objectMapper = new ObjectMapper();
    }

    // ── S3 helpers ──────────────────────────────────────────────────────────

    private String accessKey(String username) {
        return "users/" + normalize(username) + "/calendar-access.json";
    }

    private CalendarAccessData loadAccess(String username) {
        try {
            GetObjectRequest req = GetObjectRequest.builder()
                .bucket(bucketName).key(accessKey(username)).build();
            ResponseBytes<?> bytes = s3Client.getObjectAsBytes(req);
            return objectMapper.readValue(bytes.asByteArray(), CalendarAccessData.class);
        } catch (NoSuchKeyException e) {
            return new CalendarAccessData();
        } catch (Exception e) {
            e.printStackTrace();
            return new CalendarAccessData();
        }
    }

    private void saveAccess(String username, CalendarAccessData data) throws IOException {
        String json = objectMapper.writeValueAsString(data);
        PutObjectRequest req = PutObjectRequest.builder()
            .bucket(bucketName).key(accessKey(username))
            .contentType("application/json").build();
        s3Client.putObject(req, RequestBody.fromBytes(json.getBytes(StandardCharsets.UTF_8)));
    }

    // ── Send invite (owner invites friend) ──────────────────────────────────

    public CalendarInvite sendInvite(String fromUsername, String toUsername, String level, boolean requireApproval) throws IOException {
        String from = normalize(fromUsername);
        String to   = normalize(toUsername);

        CalendarInvite invite = new CalendarInvite(
            UUID.randomUUID().toString(), from, to, level, requireApproval,
            ZonedDateTime.now(ZoneOffset.UTC).format(FORMATTER)
        );

        lock.lock();
        try {
            // Add to sender's outgoing
            CalendarAccessData fromData = loadAccess(from);
            // Remove any existing invite to same person first
            fromData.getPendingOutgoing().removeIf(i -> i.getToUsername().equalsIgnoreCase(to));
            fromData.getPendingOutgoing().add(invite);
            saveAccess(from, fromData);

            // Add to recipient's incoming
            CalendarAccessData toData = loadAccess(to);
            toData.getPendingIncoming().removeIf(i -> i.getFromUsername().equalsIgnoreCase(from));
            toData.getPendingIncoming().add(invite);
            saveAccess(to, toData);
        } finally {
            lock.unlock();
        }

        return invite;
    }

    // ── Respond to invite ────────────────────────────────────────────────────

    public boolean respondToInvite(String recipientUsername, String inviteId, boolean accept) throws IOException {
        String recipient = normalize(recipientUsername);
        lock.lock();
        try {
            CalendarAccessData recipientData = loadAccess(recipient);
            Optional<CalendarInvite> found = recipientData.getPendingIncoming()
                .stream().filter(i -> i.getId().equals(inviteId)).findFirst();
            if (found.isEmpty()) return false;

            CalendarInvite invite = found.get();
            String sender = normalize(invite.getFromUsername());

            // Remove from recipient's incoming
            recipientData.getPendingIncoming().removeIf(i -> i.getId().equals(inviteId));

            if (accept) {
                // Recipient stores sender in receivedAccess — "sender gave ME access to their calendar"
                CalendarAccessGrant grant = new CalendarAccessGrant(
                    sender, invite.getLevel(), invite.isRequireApproval(),
                    ZonedDateTime.now(ZoneOffset.UTC).format(FORMATTER)
                );
                recipientData.getReceivedAccess().removeIf(g -> g.getFriendUsername().equalsIgnoreCase(sender));
                recipientData.getReceivedAccess().add(grant);
            }
            saveAccess(recipient, recipientData);

            // Remove from sender's outgoing; on accept, record grant on sender side too
            CalendarAccessData senderData = loadAccess(sender);
            senderData.getPendingOutgoing().removeIf(i -> i.getId().equals(inviteId));
            if (accept) {
                // Sender stores that recipient has access to THEIR calendar
                CalendarAccessGrant grantOnSender = new CalendarAccessGrant(
                    recipient, invite.getLevel(), invite.isRequireApproval(),
                    ZonedDateTime.now(ZoneOffset.UTC).format(FORMATTER)
                );
                senderData.getGranted().removeIf(g -> g.getFriendUsername().equalsIgnoreCase(recipient));
                senderData.getGranted().add(grantOnSender);
            }
            saveAccess(sender, senderData);

            return true;
        } finally {
            lock.unlock();
        }
    }

    // ── Get access data ──────────────────────────────────────────────────────

    public CalendarAccessData getAccessData(String username) {
        return loadAccess(normalize(username));
    }

    // ── Check if requester has view access to owner's calendar ───────────────

    public boolean hasViewAccess(String ownerUsername, String requesterUsername) {
        String owner = normalize(ownerUsername);
        String requester = normalize(requesterUsername);
        // The grant is stored on the requester's side (they have access to owner's cal)
        // AND on the owner's side (they granted access to requester)
        // We check the owner's granted list for the requester
        CalendarAccessData ownerData = loadAccess(owner);
        return ownerData.getGranted().stream()
            .anyMatch(g -> g.getFriendUsername().equalsIgnoreCase(requester));
    }

    public boolean hasAddAccess(String ownerUsername, String requesterUsername) {
        String owner = normalize(ownerUsername);
        String requester = normalize(requesterUsername);
        CalendarAccessData ownerData = loadAccess(owner);
        return ownerData.getGranted().stream()
            .anyMatch(g -> g.getFriendUsername().equalsIgnoreCase(requester)
                        && "add".equalsIgnoreCase(g.getLevel()));
    }

    public boolean requiresApproval(String ownerUsername, String requesterUsername) {
        String owner = normalize(ownerUsername);
        String requester = normalize(requesterUsername);
        CalendarAccessData ownerData = loadAccess(owner);
        return ownerData.getGranted().stream()
            .filter(g -> g.getFriendUsername().equalsIgnoreCase(requester))
            .findFirst()
            .map(CalendarAccessGrant::isRequireApproval)
            .orElse(true);
    }

    // ── Get visible events for a requester viewing owner's calendar ───────────

    public List<EventDto> getSharedEvents(String ownerUsername, String requesterUsername,
                                          List<EventDto> allOwnerEvents) {
        if (!hasViewAccess(ownerUsername, requesterUsername)) return Collections.emptyList();
        return allOwnerEvents.stream()
            .filter(e -> e.isFriendsCanSee())
            .filter(e -> "approved".equals(e.getStatus()))
            .collect(Collectors.toList());
    }

    // ── Approve / reject a pending event ────────────────────────────────────

    public boolean approveEvent(String ownerUsername, String eventId) throws IOException {
        return setEventStatus(normalize(ownerUsername), eventId, "approved");
    }

    public boolean rejectEvent(String ownerUsername, String eventId) throws IOException {
        // Rejection removes the event entirely from the owner's calendar
        String owner = normalize(ownerUsername);
        String calKey = "users/" + owner + "/calendar.json";
        lock.lock();
        try {
            List<EventDto> events = loadCalendar(owner);
            boolean removed = events.removeIf(e -> e.getId().equals(eventId) && "pending".equals(e.getStatus()));
            if (!removed) return false;
            saveCalendar(owner, events);
            return true;
        } finally {
            lock.unlock();
        }
    }

    private boolean setEventStatus(String owner, String eventId, String status) throws IOException {
        lock.lock();
        try {
            List<EventDto> events = loadCalendar(owner);
            for (EventDto e : events) {
                if (e.getId().equals(eventId)) {
                    e.setStatus(status);
                    saveCalendar(owner, events);
                    return true;
                }
            }
            return false;
        } finally {
            lock.unlock();
        }
    }

    // ── Revoke access ────────────────────────────────────────────────────────

    public boolean revokeAccess(String ownerUsername, String friendUsername, boolean keepEvents) throws IOException {
        String owner  = normalize(ownerUsername);
        String friend = normalize(friendUsername);
        lock.lock();
        try {
            // Remove from owner's granted list
            CalendarAccessData ownerData = loadAccess(owner);
            ownerData.getGranted().removeIf(g -> g.getFriendUsername().equalsIgnoreCase(friend));
            saveAccess(owner, ownerData);

            // Remove from friend's receivedAccess list (they no longer have access to owner's cal)
            CalendarAccessData friendData = loadAccess(friend);
            friendData.getReceivedAccess().removeIf(g -> g.getFriendUsername().equalsIgnoreCase(owner));
            // Also clean any stale entry in granted (backward compat with old data)
            friendData.getGranted().removeIf(g -> g.getFriendUsername().equalsIgnoreCase(owner));
            saveAccess(friend, friendData);

            // Optionally delete events added by the friend from owner's calendar
            if (!keepEvents) {
                List<EventDto> events = loadCalendar(owner);
                events.removeIf(e -> friend.equalsIgnoreCase(normalize(e.getAddedBy() != null ? e.getAddedBy() : "")));
                saveCalendar(owner, events);
            }
            return true;
        } finally {
            lock.unlock();
        }
    }

    // ── Calendar load/save helpers ───────────────────────────────────────────

    public List<EventDto> loadCalendar(String username) {
        try {
            String key = "users/" + normalize(username) + "/calendar.json";
            GetObjectRequest req = GetObjectRequest.builder().bucket(bucketName).key(key).build();
            ResponseBytes<?> bytes = s3Client.getObjectAsBytes(req);
            return objectMapper.readValue(bytes.asByteArray(), new TypeReference<List<EventDto>>() {});
        } catch (NoSuchKeyException e) {
            return new ArrayList<>();
        } catch (Exception e) {
            e.printStackTrace();
            return new ArrayList<>();
        }
    }

    public void saveCalendar(String username, List<EventDto> events) throws IOException {
        String key = "users/" + normalize(username) + "/calendar.json";
        String json = objectMapper.writeValueAsString(events);
        PutObjectRequest req = PutObjectRequest.builder()
            .bucket(bucketName).key(key).contentType("application/json").build();
        s3Client.putObject(req, RequestBody.fromBytes(json.getBytes(StandardCharsets.UTF_8)));
    }
}
