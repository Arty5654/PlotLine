-- the friends feed can also show weekly goals (a post has either goal or weekly_goal)
alter table feed_posts add column weekly_goal jsonb;
