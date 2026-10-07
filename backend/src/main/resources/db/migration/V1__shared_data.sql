-- Data every user shares, moved out of single S3 files (all-users.json, email-index.json,
-- friends-feed/posts.json) so two updates at once can't overwrite each other. Per-user data
-- (account.json, budgets, ...) is still in S3 for now.

-- one row per account: usernames and emails are unique, and signup_number says who signed up first
create table accounts (
    username         text primary key,               -- normalized (lowercase)
    display_username text not null,                  -- as typed at sign-up
    email            text unique,                    -- lowercase
    signup_number    bigint generated always as identity unique,
    created_at       timestamptz not null default now()
);

-- the friends feed: one row per shared goal
create table feed_posts (
    id        uuid primary key,
    seq       bigint generated always as identity unique,  -- posting order
    username  text not null,                               -- author, as sent by the app
    author    text not null,                               -- author, normalized
    goal      jsonb,
    comment   text,
    liked_by  text[] not null default '{}',
    comments  jsonb not null default '[]'                  -- ["name: text", ...]
);
create index feed_posts_author on feed_posts (author, seq);

-- memberships (see MembershipService)
create table memberships (
    username                text primary key,
    plan                    text not null,
    expires_at              bigint,          -- epoch millis
    transaction_expires_at  bigint,
    auto_renews             boolean,
    revoked                 boolean not null default false,
    original_transaction_id text,
    environment             text
);

-- each App Store subscription unlocks one account
create table app_store_subscriptions (
    original_transaction_id text primary key,
    username                text not null
);

-- one-time copies of the old S3 files (see S3DataImport)
create table data_imports (
    name        text primary key,
    imported_at timestamptz not null default now()
);
