CREATE TABLE users (
  id text PRIMARY KEY,
  address text,
  seed text
);

CREATE TABLE things (
  id text PRIMARY KEY,
  created_at timestamp NOT NULL DEFAULT now(),
  created_by text NOT NULL REFERENCES users(id),
  actual_date timestamp NOT NULL DEFAULT now(),
  name text DEFAULT '',
  asset text NOT NULL,
  txn text DEFAULT ''
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
  thing_id text NOT NULL REFERENCES things(id),
  user_id text REFERENCES users(id),
  account_name text NOT NULL,

  paid text DEFAULT '0',
  due text DEFAULT '0',
  confirmed boolean DEFAULT false,
  note text DEFAULT '',

  added_by text REFERENCES users(id)
);
