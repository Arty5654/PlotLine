package com.plotline.backend.dto;

import java.util.List;
import java.util.ArrayList;

public class FriendList {
    private String username;
    private List<String> friends;

    public FriendList() {
      this.friends = new ArrayList<String>();
    }

    public FriendList(String username, List<String> friends) {
        this.username = username;
        this.friends = friends;
    }

    public String getUsername() {
        return username;
    }
    public void setUsername(String username) {
        this.username = username;
    }
    public List<String> getFriends() {
        return friends;
    }
    public void setFriends(List<String> friends) {
        this.friends = friends;
    }
}
