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
            // Convert EventRequest to an EventDto
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

            EventDto createdEvent = calendarService.createEvent(newEvent, request.getUsername());
            return ResponseEntity.ok(new EventResponse(true, null, createdEvent));
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(new EventResponse(false, e.getMessage(), null));
        }
    }

    @PostMapping("/update-event")
    public ResponseEntity<EventResponse> updateEvent(@RequestBody EventRequest request) {
        try {
            // Convert EventRequest to an EventDto
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

