-- shared grocery price estimates, so the same item costs the same everywhere in a region and isn't
-- re-estimated by AI every time (refreshed when older than two weeks)
create table grocery_prices (
    item       text not null,                    -- normalized item name ("whole milk")
    region     text not null,                    -- state or country ("ohio", "united states")
    unit_price numeric(10, 2) not null,          -- for one of the item
    updated_at timestamptz not null default now(),
    primary key (item, region)
);
