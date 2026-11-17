-- AI price estimates shared by everyone in a place (a state's gas price, a city's transit fare,
-- rideshare rates, the tolls on a route), so the same question isn't asked again and again and
-- everyone in a place sees the same number; refreshed when older than the kind's limit
create table price_estimates (
    kind       text not null,                    -- "gas", "electricity", "transit", "rideshare", "tolls"
    place      text not null,                    -- normalized place ("virginia", "arlington, va -> washington, dc")
    data       text not null,                    -- the numbers, as JSON
    updated_at timestamptz not null default now(),
    primary key (kind, place)
);
