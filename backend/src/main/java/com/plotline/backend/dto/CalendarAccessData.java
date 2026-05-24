package com.plotline.backend.dto;

import java.util.ArrayList;
import java.util.List;

public class CalendarAccessData {
    private List<CalendarAccessGrant> granted = new ArrayList<>();         // friends I gave access to MY calendar
    private List<CalendarAccessGrant> receivedAccess = new ArrayList<>();  // friends who gave ME access to THEIR calendar
    private List<CalendarInvite> pendingOutgoing = new ArrayList<>();
    private List<CalendarInvite> pendingIncoming = new ArrayList<>();

    public CalendarAccessData() {}

    public List<CalendarAccessGrant> getGranted() { return granted; }
    public void setGranted(List<CalendarAccessGrant> granted) { this.granted = granted; }

    public List<CalendarAccessGrant> getReceivedAccess() { return receivedAccess; }
    public void setReceivedAccess(List<CalendarAccessGrant> receivedAccess) { this.receivedAccess = receivedAccess; }

    public List<CalendarInvite> getPendingOutgoing() { return pendingOutgoing; }
    public void setPendingOutgoing(List<CalendarInvite> pendingOutgoing) { this.pendingOutgoing = pendingOutgoing; }

    public List<CalendarInvite> getPendingIncoming() { return pendingIncoming; }
    public void setPendingIncoming(List<CalendarInvite> pendingIncoming) { this.pendingIncoming = pendingIncoming; }
}
