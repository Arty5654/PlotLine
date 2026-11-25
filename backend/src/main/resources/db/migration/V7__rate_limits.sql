-- Rate limits shared by every server machine: one row per limit, key (a user or an IP) and time
-- window, counting the requests in it. A request adds one with a single upsert; old windows are
-- deleted once they're over (expires_at).
create table rate_limit_hits (
    bucket       text    not null,               -- "API_PER_USER:alex:60" (limit, key, window in seconds)
    window_start bigint  not null,               -- epoch seconds the window started
    hits         integer not null,
    expires_at   timestamptz not null,           -- when the window ends
    primary key (bucket, window_start)
);

create index rate_limit_hits_expires on rate_limit_hits (expires_at);
