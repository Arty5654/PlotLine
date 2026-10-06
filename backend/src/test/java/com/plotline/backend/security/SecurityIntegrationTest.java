package com.plotline.backend.security;

import com.plaid.client.request.PlaidApi;
import com.plotline.backend.config.ApiKeyFilter;
import com.plotline.backend.controller.AuthController;
import com.plotline.backend.controller.CalendarAccessController;
import com.plotline.backend.controller.CalendarController;
import com.plotline.backend.controller.ChatController;
import com.plotline.backend.controller.FriendsController;
import com.plotline.backend.controller.PlaidController;
import com.plotline.backend.controller.ProfileController;
import com.plotline.backend.controller.SmsController;
import com.plotline.backend.controller.WeeklyGoalsController;
import com.plotline.backend.dto.AuthResponse;
import com.plotline.backend.dto.EventDto;
import com.plotline.backend.dto.FriendList;
import com.plotline.backend.dto.RequestList;
import com.plotline.backend.dto.UserProfile;
import com.plotline.backend.plaid.TokenStore;
import com.plotline.backend.service.AccountDeletionService;
import com.plotline.backend.service.AppleSignInService;
import com.plotline.backend.service.AuthService;
import com.plotline.backend.service.CalendarAccessService;
import com.plotline.backend.service.CalendarService;
import com.plotline.backend.service.ChatMessageService;
import com.plotline.backend.service.FriendsFeedService;
import com.plotline.backend.service.FriendsService;
import com.plotline.backend.service.LongTermGoalsService;
import com.plotline.backend.service.S3Service;
import com.plotline.backend.service.SmsService;
import com.plotline.backend.service.UserProfileService;
import com.plotline.backend.service.WeeklyGoalsService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.context.annotation.ComponentScan;
import org.springframework.context.annotation.FilterType;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

import java.util.ArrayList;
import java.util.List;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Real HTTP requests through the login-token filter, the ownership interceptor and body checks.
 * Services are mocked; "alice-token" signs in as alice, any other token is invalid.
 */
@WebMvcTest(
        controllers = {AuthController.class, FriendsController.class, CalendarController.class,
                CalendarAccessController.class, ChatController.class, ProfileController.class,
                PlaidController.class, WeeklyGoalsController.class, SmsController.class},
        excludeFilters = @ComponentScan.Filter(type = FilterType.ASSIGNABLE_TYPE, classes = ApiKeyFilter.class))
class SecurityIntegrationTest {

    @Autowired private MockMvc mockMvc;

    @MockBean private AuthService authService;
    @MockBean private AppleSignInService appleSignInService;
    @MockBean private AccountDeletionService accountDeletionService;
    @MockBean private FriendsService friendsService;
    @MockBean private CalendarService calendarService;
    @MockBean private CalendarAccessService calendarAccessService;
    @MockBean private ChatMessageService chatMessageService;
    @MockBean private UserProfileService userProfileService;
    @MockBean private PlaidApi plaidApi;
    @MockBean private TokenStore tokenStore;
    @MockBean private S3Service s3Service;
    @MockBean private WeeklyGoalsService weeklyGoalsService;
    @MockBean private LongTermGoalsService longTermGoalsService;
    @MockBean private SmsService smsService;
    @MockBean private FriendsFeedService friendsFeedService;

    @BeforeEach
    void signIn() throws Exception {
        when(authService.authenticatedUsername("alice-token")).thenReturn("alice");
        when(authService.normalizeUsername(anyString())).thenAnswer(i -> ((String) i.getArgument(0)).trim().toLowerCase());
        when(friendsService.getFriendList("alice")).thenReturn(friends("alice", "carol"));
        when(friendsService.getFriendRequests("alice")).thenReturn(requests("alice"));
    }

    private static MockHttpServletRequestBuilder asAlice(MockHttpServletRequestBuilder request) {
        return request.header("Authorization", "Bearer alice-token");
    }

    private static MockHttpServletRequestBuilder json(MockHttpServletRequestBuilder request, String body) {
        return asAlice(request).contentType(MediaType.APPLICATION_JSON).content(body);
    }

    private static FriendList friends(String owner, String... names) {
        FriendList list = new FriendList();
        list.setUsername(owner);
        list.setFriends(new ArrayList<>(List.of(names)));
        return list;
    }

    private static RequestList requests(String owner, String... names) {
        RequestList list = new RequestList();
        list.setUsername(owner);
        list.setPendingRequests(new ArrayList<>(List.of(names)));
        return list;
    }

    @Nested
    @DisplayName("Login token")
    class LoginToken {
        @Test
        @DisplayName("Protected endpoints reject requests with no token")
        void missingToken() throws Exception {
            mockMvc.perform(get("/friends/get-friends").param("username", "alice"))
                    .andExpect(status().isUnauthorized())
                    .andExpect(jsonPath("$.success").value(false));
            verify(friendsService, never()).getFriendList(any());
        }

        @Test
        @DisplayName("Protected endpoints reject invalid, expired or old tokens")
        void invalidToken() throws Exception {
            mockMvc.perform(get("/friends/get-friends").param("username", "alice")
                            .header("Authorization", "Bearer forged"))
                    .andExpect(status().isUnauthorized());
            mockMvc.perform(get("/friends/get-friends").param("username", "alice")
                            .header("Authorization", "alice-token")) // missing "Bearer "
                    .andExpect(status().isUnauthorized());
        }

        @Test
        @DisplayName("A valid token gets through")
        void validToken() throws Exception {
            mockMvc.perform(asAlice(get("/friends/get-friends").param("username", "alice")))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.friends[0]").value("carol"));
        }

        @Test
        @DisplayName("Sign-in works without a token")
        void signInIsPublic() throws Exception {
            when(authService.normalizeUsername("bob")).thenReturn("bob");
            when(authService.userExists("bob")).thenReturn(true);
            when(authService.userLogin("bob", "pw")).thenReturn("true");
            when(authService.generateToken("bob")).thenReturn("bob-token");

            mockMvc.perform(post("/auth/signin").contentType(MediaType.APPLICATION_JSON)
                            .content("{\"username\":\"bob\",\"password\":\"pw\"}"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.token").value("bob-token"));
        }

        @Test
        @DisplayName("Refresh swaps a valid token for a new one")
        void refresh() throws Exception {
            when(authService.needsPhoneVerification("alice")).thenReturn(false);
            when(authService.generateToken("alice")).thenReturn("fresh-token");
            when(authService.getDisplayUsername("alice")).thenReturn("Alice");

            mockMvc.perform(asAlice(post("/auth/refresh")))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.token").value("fresh-token"))
                    .andExpect(jsonPath("$.displayUsername").value("Alice"));
            mockMvc.perform(post("/auth/refresh")).andExpect(status().isUnauthorized());
        }

        @Test
        @DisplayName("Delete account deletes the token's user; naming someone else is rejected")
        void deleteAccountUsesToken() throws Exception {
            when(accountDeletionService.deleteAccount(eq("alice"), any())).thenReturn(new AuthResponse(true, null, null));

            mockMvc.perform(json(post("/auth/delete-account"), "{\"appleAuthorizationCode\":\"c1\"}"))
                    .andExpect(status().isOk());
            verify(accountDeletionService).deleteAccount("alice", "c1");

            mockMvc.perform(json(post("/auth/delete-account"), "{\"username\":\"victim\"}"))
                    .andExpect(status().isForbidden());
            verify(accountDeletionService, never()).deleteAccount(eq("victim"), any());

            mockMvc.perform(post("/auth/delete-account").contentType(MediaType.APPLICATION_JSON).content("{}"))
                    .andExpect(status().isUnauthorized());
        }
    }

    @Nested
    @DisplayName("Your own data only")
    class Ownership {
        @Test
        @DisplayName("Path variable naming another user is rejected")
        void pathVariable() throws Exception {
            mockMvc.perform(asAlice(get("/api/goals/bob"))).andExpect(status().isForbidden());
            verify(weeklyGoalsService, never()).getWeeklyGoals(any());
        }

        @Test
        @DisplayName("Query parameter naming another user is rejected; case doesn't matter for your own")
        void queryParam() throws Exception {
            mockMvc.perform(asAlice(get("/friends/get-friends").param("username", "bob")))
                    .andExpect(status().isForbidden());
            mockMvc.perform(asAlice(get("/friends/get-friends").param("username", "Alice")))
                    .andExpect(status().isOk());
        }

        @Test
        @DisplayName("JSON body field naming another user is rejected (map body)")
        void mapBody() throws Exception {
            mockMvc.perform(json(post("/auth/change-password"),
                            "{\"username\":\"bob\",\"oldPassword\":\"a\",\"newPassword\":\"b\"}"))
                    .andExpect(status().isForbidden());
            verify(authService, never()).changeUserPassword(any(), any(), any(), any());
        }

        @Test
        @DisplayName("JSON body field naming another user is rejected (record body)")
        void recordBody() throws Exception {
            mockMvc.perform(json(post("/api/plaid/exchange"),
                            "{\"username\":\"bob\",\"public_token\":\"p\",\"account_ids\":[]}"))
                    .andExpect(status().isForbidden());
            verify(tokenStore, never()).saveAccessToken(any(), any(), any());
        }

        @Test
        @DisplayName("Multipart/form field naming another user is rejected")
        void formParam() throws Exception {
            mockMvc.perform(asAlice(post("/profile/increment-trophies").param("username", "bob")
                            .param("trophyId", "t").param("amount", "1")))
                    .andExpect(status().isForbidden());
        }

        @Test
        @DisplayName("Chat messages can only be posted as yourself")
        void chatPostAsSelf() throws Exception {
            mockMvc.perform(json(post("/chat").param("userId", "alice"), "{\"creator\":\"bob\",\"content\":\"hi\"}"))
                    .andExpect(status().isForbidden());
            mockMvc.perform(json(post("/chat").param("userId", "bob"), "{\"content\":\"hi\"}"))
                    .andExpect(status().isForbidden());
        }
    }

    @Nested
    @DisplayName("Friends")
    class Friends {
        @Test
        @DisplayName("Sending a request: you must be the sender")
        void sendRequest() throws Exception {
            when(friendsService.createOrUpdateFriendRequest(any())).thenReturn("Successfully sent request!");

            mockMvc.perform(json(put("/friends/request"),
                            "{\"senderUsername\":\"alice\",\"receiverUsername\":\"bob\",\"status\":\"PENDING\"}"))
                    .andExpect(status().isOk());
            mockMvc.perform(json(put("/friends/request"),
                            "{\"senderUsername\":\"bob\",\"receiverUsername\":\"dave\",\"status\":\"PENDING\"}"))
                    .andExpect(status().isForbidden());
        }

        @Test
        @DisplayName("Accepting: only the receiver, and only a request that really exists")
        void acceptRequest() throws Exception {
            when(friendsService.getFriendRequests("alice")).thenReturn(requests("alice", "bob"));
            when(friendsService.createOrUpdateFriendRequest(any())).thenReturn("Accepted");

            mockMvc.perform(json(put("/friends/request"),
                            "{\"senderUsername\":\"bob\",\"receiverUsername\":\"alice\",\"status\":\"ACCEPTED\"}"))
                    .andExpect(status().isOk());
            // nobody named eve asked to be friends
            mockMvc.perform(json(put("/friends/request"),
                            "{\"senderUsername\":\"eve\",\"receiverUsername\":\"alice\",\"status\":\"ACCEPTED\"}"))
                    .andExpect(status().isForbidden());
            // can't accept a request on someone else's behalf
            mockMvc.perform(json(put("/friends/request"),
                            "{\"senderUsername\":\"alice\",\"receiverUsername\":\"bob\",\"status\":\"ACCEPTED\"}"))
                    .andExpect(status().isForbidden());
        }

        @Test
        @DisplayName("Someone else's pending requests only show whether you sent one")
        void othersRequestsFiltered() throws Exception {
            when(friendsService.getFriendRequests("bob")).thenReturn(requests("bob", "alice", "carol", "dave"));

            mockMvc.perform(asAlice(get("/friends/get-friend-requests").param("username", "bob")))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.pendingRequests.length()").value(1))
                    .andExpect(jsonPath("$.pendingRequests[0]").value("alice"));
        }

        @Test
        @DisplayName("You can only end friendships you're part of")
        void removeFriend() throws Exception {
            mockMvc.perform(json(post("/friends/remove"),
                            "{\"senderUsername\":\"bob\",\"receiverUsername\":\"carol\",\"status\":\"REMOVE\"}"))
                    .andExpect(status().isForbidden());
            mockMvc.perform(json(post("/friends/remove"),
                            "{\"senderUsername\":\"alice\",\"receiverUsername\":\"carol\",\"status\":\"REMOVE\"}"))
                    .andExpect(status().isOk());
        }
    }

    @Nested
    @DisplayName("Profiles")
    class Profiles {
        @BeforeEach
        void profiles() {
            for (String name : List.of("bob", "carol")) {
                UserProfile profile = new UserProfile();
                profile.setUsername(name);
                profile.setName(name + " Smith");
                profile.setBirthday("2000-01-01");
                profile.setCity("Boston");
                when(userProfileService.getProfile(name)).thenReturn(profile);
            }
        }

        @Test
        @DisplayName("Non-friends only see the username")
        void nonFriend() throws Exception {
            mockMvc.perform(asAlice(get("/profile/get-user").param("username", "bob")))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.username").value("bob"))
                    .andExpect(jsonPath("$.name").doesNotExist())
                    .andExpect(jsonPath("$.birthday").doesNotExist())
                    .andExpect(jsonPath("$.city").doesNotExist());
        }

        @Test
        @DisplayName("Friends see name, birthday and city")
        void friend() throws Exception {
            mockMvc.perform(asAlice(get("/profile/get-user").param("username", "carol")))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.name").value("carol Smith"))
                    .andExpect(jsonPath("$.city").value("Boston"));
        }

        @Test
        @DisplayName("Phone numbers are private")
        void phoneIsPrivate() throws Exception {
            mockMvc.perform(asAlice(get("/profile/get-phone").param("username", "carol")))
                    .andExpect(status().isForbidden());
        }

        @Test
        @DisplayName("Profile pictures and trophies are public to signed-in users")
        void publicParts() throws Exception {
            mockMvc.perform(asAlice(get("/profile/get-profile-pic").param("username", "bob")))
                    .andExpect(status().isOk());
            mockMvc.perform(asAlice(get("/profile/get-trophies").param("username", "bob")))
                    .andExpect(status().isOk());
        }
    }

    @Nested
    @DisplayName("Calendars")
    class Calendars {
        private static final String EVENT = "\"title\":\"Dinner\",\"startDate\":\"2026-10-01\",\"endDate\":\"2026-10-01\",\"eventType\":\"event\"";

        @Test
        @DisplayName("Adding to a friend's calendar needs their 'add' access")
        void addToFriendsCalendar() throws Exception {
            when(calendarService.createEvent(any(EventDto.class), anyString())).thenReturn(new EventDto());
            when(calendarAccessService.hasAddAccess("carol", "alice")).thenReturn(true);

            mockMvc.perform(json(post("/calendar/create-event"), "{\"username\":\"carol\",\"addedBy\":\"alice\"," + EVENT + "}"))
                    .andExpect(status().isOk());
            mockMvc.perform(json(post("/calendar/create-event"), "{\"username\":\"bob\",\"addedBy\":\"alice\"," + EVENT + "}"))
                    .andExpect(status().isForbidden());
            // can't pretend someone else added it
            mockMvc.perform(json(post("/calendar/create-event"), "{\"username\":\"carol\",\"addedBy\":\"dave\"," + EVENT + "}"))
                    .andExpect(status().isForbidden());
            mockMvc.perform(json(post("/calendar/create-event"), "{\"username\":\"alice\"," + EVENT + "}"))
                    .andExpect(status().isOk());
        }

        @Test
        @DisplayName("Only the owner can edit or delete their events")
        void editOwnOnly() throws Exception {
            mockMvc.perform(json(post("/calendar/delete-event"), "{\"username\":\"carol\",\"eventId\":\"e1\"}"))
                    .andExpect(status().isForbidden());
        }

        @Test
        @DisplayName("Shared calendars are requested as yourself; the service checks view access")
        void sharedEvents() throws Exception {
            mockMvc.perform(asAlice(get("/calendar-access/shared-events")
                            .param("ownerUsername", "carol").param("requesterUsername", "bob")))
                    .andExpect(status().isForbidden());
            mockMvc.perform(asAlice(get("/calendar-access/shared-events")
                            .param("ownerUsername", "carol").param("requesterUsername", "alice")))
                    .andExpect(status().isOk());
            verify(calendarAccessService).getSharedEvents(eq("carol"), eq("alice"), any());
        }

        @Test
        @DisplayName("Only the calendar owner can grant or revoke access")
        void accessChanges() throws Exception {
            mockMvc.perform(json(post("/calendar-access/send-invite"),
                            "{\"fromUsername\":\"bob\",\"toUsername\":\"carol\",\"level\":\"view\"}"))
                    .andExpect(status().isForbidden());
            mockMvc.perform(json(post("/calendar-access/revoke"),
                            "{\"ownerUsername\":\"carol\",\"friendUsername\":\"alice\"}"))
                    .andExpect(status().isForbidden());
        }
    }

    @Nested
    @DisplayName("Chat")
    class Chat {
        @Test
        @DisplayName("Reactions and replies only on your own or your friends' messages")
        void friendsOnly() throws Exception {
            mockMvc.perform(json(post("/chat/carol/m1/reactions"), "{\"emoji\":\"🔥\"}"))
                    .andExpect(status().isOk());
            mockMvc.perform(json(post("/chat/bob/m1/reactions"), "{\"emoji\":\"🔥\"}"))
                    .andExpect(status().isForbidden());
            mockMvc.perform(json(post("/chat/bob/m1/replies"), "{\"userId\":\"alice\",\"text\":\"hi\"}"))
                    .andExpect(status().isForbidden());
            mockMvc.perform(json(post("/chat/carol/m1/replies"), "{\"userId\":\"bob\",\"text\":\"hi\"}"))
                    .andExpect(status().isForbidden());
            mockMvc.perform(asAlice(delete("/chat/carol/m1/replies").param("reply", "r1")))
                    .andExpect(status().isOk());
            verify(chatMessageService).removeReply("carol", "m1", "alice", "r1");
        }
    }

    @Nested
    @DisplayName("Removed endpoints")
    class Removed {
        @Test
        @DisplayName("Raw S3 file access and arbitrary SMS sending no longer exist")
        void gone() throws Exception {
            mockMvc.perform(asAlice(get("/api/files/download/email-index.json"))).andExpect(status().isNotFound());
            mockMvc.perform(asAlice(delete("/api/files/delete/all-users.json"))).andExpect(status().isNotFound());
            mockMvc.perform(asAlice(post("/sms/send").param("toNumber", "5555550123"))).andExpect(status().isNotFound());
        }
    }
}
