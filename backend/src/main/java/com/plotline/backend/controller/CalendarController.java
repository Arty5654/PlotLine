package com.plotline.backend.controller;

import java.util.List;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import com.plotline.backend.dto.*;
import com.plotline.backend.service.CalendarService;

@RestController
@RequestMapping("/calendar")
public class CalendarController {

    private final CalendarService calendarService;

    @Autowired
    public CalendarController(CalendarService calendarService) {
        this.calendarService = calendarService;
    }

    @GetMapping("/get-events")
    public ResponseEntity<EventsResponse> getEvents(@RequestParam String username) {
        try {
            List<EventDto> eventList = calendarService.getEvents(username);
            return ResponseEntity.ok(new EventsResponse(true, null, eventList));
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(new EventsResponse(false, e.getMessage(), null));
        }
    }

    @PostMapping("/create-event")
    public ResponseEntity<EventResponse> createEvent(@RequestBody EventRequest request) {
        try {
            EventDto newEvent = new EventDto(
                request.getId(),
                request.getTitle(),
                request.getDescription(),
                request.getStartDate(),
                request.getEndDate(),
                request.getEventType(),
                request.getRecurrence(),
                request.getInvitedFriends()
            );
            newEvent.setFriendsCanSee(request.isFriendsCanSee());
            newEvent.setAddedBy(request.getAddedBy());
            newEvent.setStatus(request.getStatus());
            if (request.getInviteStatuses() != null) newEvent.setInviteStatuses(request.getInviteStatuses());

            EventDto createdEvent = calendarService.createEvent(newEvent, request.getUsername());
            return ResponseEntity.ok(new EventResponse(true, null, createdEvent));
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(new EventResponse(false, e.getMessage(), null));
        }
    }

    @PostMapping("/update-event")
    public ResponseEntity<EventResponse> updateEvent(@RequestBody EventRequest request) {
        try {
            EventDto updatedEvent = new EventDto(
                request.getId(),
                request.getTitle(),
                request.getDescription(),
                request.getStartDate(),
                request.getEndDate(),
                request.getEventType(),
                request.getRecurrence(),
                request.getInvitedFriends()
            );
            updatedEvent.setFriendsCanSee(request.isFriendsCanSee());
            updatedEvent.setAddedBy(request.getAddedBy());
            updatedEvent.setStatus(request.getStatus());
            if (request.getInviteStatuses() != null) updatedEvent.setInviteStatuses(request.getInviteStatuses());

            EventDto savedEvent = calendarService.updateEvent(updatedEvent, request.getUsername());
            return ResponseEntity.ok(new EventResponse(true, null, savedEvent));
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(new EventResponse(false, e.getMessage(), null));
        }
    }

    @PostMapping("/delete-event")
    public ResponseEntity<EventResponse> deleteEvent(@RequestBody DeleteEventRequest request) {
      try {
          calendarService.deleteEvent(request.getEventId(), request.getUsername());
          return ResponseEntity.ok(new EventResponse(true, null, null));
      } catch (Exception e) {
          return ResponseEntity.badRequest().body(new EventResponse(false, e.getMessage(), null));
      }
    }

    // POST /calendar/respond-event-invite
    // Body: { username, eventId, accept }
    @PostMapping("/respond-event-invite")
    public ResponseEntity<String> respondToEventInvite(@RequestBody java.util.Map<String, Object> body) {
        try {
            String username = (String) body.get("username");
            String eventId  = (String) body.get("eventId");
            boolean accept  = Boolean.TRUE.equals(body.get("accept"));
            boolean ok = calendarService.respondToEventInvite(username, eventId, accept);
            return ok ? ResponseEntity.ok("Success") : ResponseEntity.badRequest().body("Invite not found");
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }

    @PostMapping("/batch-sync-gcal")
    public ResponseEntity<EventsResponse> batchSyncGcal(@RequestBody BatchSyncGcalRequest request) {
        try {
            List<EventDto> result = calendarService.batchSyncGcalEvents(request.getUsername(), request.getEvents());
            return ResponseEntity.ok(new EventsResponse(true, null, result));
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(new EventsResponse(false, e.getMessage(), null));
        }
    }

    @DeleteMapping("/delete-by-type")
    public ResponseEntity<String> deleteEventsByType(@RequestParam String username, @RequestParam String type) {
        try {
            calendarService.deleteEventsByType(username, type);
            return ResponseEntity.ok("Event deleted successfully");
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }


}

