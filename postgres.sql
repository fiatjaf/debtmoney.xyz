CREATE TABLE users (
  id text PRIMARY KEY,
  address text,
  seed text
);

CREATE TABLE things (
  id text PRIMARY KEY,
  created_at timestamp DEFAULT now(),
  thing_date timestamp DEFAULT now(),
  name text,
  asset text,
  txn text
);

CREATE FUNCTION publishable(things) RETURNS boolean AS $$
  SELECT total = confirmed FROM (
    SELECT
      count(*) AS total,
      sum(confirmed::int) AS confirmed
    FROM parties WHERE thing_id = $1.id
    GROUP BY thing_id
  )x;
$$ LANGUAGE SQL;

CREATE TABLE parties (
  thing_id text REFERENCES things(id),
  user_id text REFERENCES users(id),

  paid text,
  due text,
  confirmed boolean,
  note text
);

CREATE FUNCTION registered(parties) RETURNS boolean AS $$
  SELECT $1.user_id ~* '^[a-z0-9_]+$';
$$ LANGUAGE SQL;
