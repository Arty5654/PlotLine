package com.plotline.backend.controller;

import com.plotline.backend.dto.*;
import com.plotline.backend.service.CalendarAccessService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/calendar-access")
public class CalendarAccessController {

    private final CalendarAccessService calendarAccessService;

    public CalendarAccessController(CalendarAccessService calendarAccessService) {
        this.calendarAccessService = calendarAccessService;
    }

    // POST /calendar-access/send-invite
    @PostMapping("/send-invite")
    public ResponseEntity<?> sendInvite(@RequestBody CalendarAccessRequest req) {
        try {
            CalendarInvite invite = calendarAccessService.sendInvite(
                req.getFromUsername(), req.getToUsername(),
                req.getLevel(), req.isRequireApproval()
            );
            return ResponseEntity.ok(invite);
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }

    // POST /calendar-access/respond-invite
    @PostMapping("/respond-invite")
    public ResponseEntity<?> respondToInvite(@RequestBody CalendarAccessRequest req) {
        try {
            boolean ok = calendarAccessService.respondToInvite(
                req.getRecipientUsername(), req.getInviteId(), req.isAccept()
            );
            return ok ? ResponseEntity.ok("Success") : ResponseEntity.badRequest().body("Invite not found");
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }

    // GET /calendar-access/data?username=
    @GetMapping("/data")
    public ResponseEntity<?> getAccessData(@RequestParam String username) {
        try {
            CalendarAccessData data = calendarAccessService.getAccessData(username);
            return ResponseEntity.ok(data);
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }

    // GET /calendar-access/shared-events?ownerUsername=&requesterUsername=
    @GetMapping("/shared-events")
    public ResponseEntity<?> getSharedEvents(
            @RequestParam String ownerUsername,
            @RequestParam String requesterUsername) {
        try {
            List<EventDto> ownerEvents = calendarAccessService.loadCalendar(ownerUsername);
            List<EventDto> shared = calendarAccessService.getSharedEvents(ownerUsername, requesterUsername, ownerEvents);
            return ResponseEntity.ok(shared);
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }

    // POST /calendar-access/approve-event
    @PostMapping("/approve-event")
    public ResponseEntity<?> approveEvent(@RequestBody CalendarAccessRequest req) {
        try {
            boolean ok = calendarAccessService.approveEvent(req.getOwnerUsername(), req.getEventId());
            return ok ? ResponseEntity.ok("Approved") : ResponseEntity.badRequest().body("Event not found");
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }

    // POST /calendar-access/reject-event
    @PostMapping("/reject-event")
    public ResponseEntity<?> rejectEvent(@RequestBody CalendarAccessRequest req) {
        try {
            boolean ok = calendarAccessService.rejectEvent(req.getOwnerUsername(), req.getEventId());
            return ok ? ResponseEntity.ok("Rejected") : ResponseEntity.badRequest().body("Event not found or not pending");
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }

    // POST /calendar-access/revoke
    @PostMapping("/revoke")
    public ResponseEntity<?> revokeAccess(@RequestBody CalendarAccessRequest req) {
        try {
            boolean ok = calendarAccessService.revokeAccess(
                req.getOwnerUsername(), req.getFriendUsername(), req.isKeepEvents()
            );
            return ok ? ResponseEntity.ok("Access revoked") : ResponseEntity.badRequest().body("Failed");
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }
}
