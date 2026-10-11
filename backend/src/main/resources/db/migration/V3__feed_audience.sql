-- who can see a post: null = all the author's friends, otherwise only these (normalized) usernames
alter table feed_posts add column audience text[];
