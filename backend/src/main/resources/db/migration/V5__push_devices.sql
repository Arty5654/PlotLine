-- phones that get push notifications (one row per phone; a phone signed in to a new account moves to it)
create table push_devices (
    token       text primary key,                 -- APNs device token (hex)
    username    text not null,
    environment text not null,                    -- "production" (App Store / TestFlight) or "sandbox" (Xcode)
    time_zone   text,                             -- "America/New_York": when Sunday 6 PM is for the weekly recap
    updated_at  timestamptz not null default now()
);
create index push_devices_username on push_devices (username);

-- weekly budget recaps already sent, so each person gets one per week
create table weekly_recaps (
    username text not null,
    week     text not null,                       -- "2026-W42" (Sunday-start weeks, like spending)
    sent_at  timestamptz not null default now(),
    primary key (username, week)
);
