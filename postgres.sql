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
  total_due text,
  name text,
  asset text NOT NULL,
  txn text DEFAULT '',

  CONSTRAINT positive CHECK (total_due::NUMERIC > 0),
  CONSTRAINT name_notempty CHECK (name != ''),
  CONSTRAINT asset_notempty CHECK (asset != '')
);

CREATE TABLE parties (
  thing_id text NOT NULL REFERENCES things(id),
  user_id text REFERENCES users(id),
  account_name text NOT NULL,

  paid text,
  due text,
  confirmed boolean DEFAULT false,
  note text DEFAULT '',

  added_by text REFERENCES users(id),

  CONSTRAINT numeric_due CHECK (due::NUMERIC >= 0),
  CONSTRAINT numeric_paid CHECK (paid::NUMERIC >= 0)
);

CREATE FUNCTION thing_totals() RETURNS trigger AS $thing_totals$
  DECLARE
    tid text;
    total numeric;
    parties_due numeric;
    parties_paid numeric;
  BEGIN
    IF TG_TABLE_NAME = 'things' THEN
      tid = NEW.id;
      total = NEW.total_due::numeric;
    ELSE
      tid = NEW.thing_id;
      SELECT total_due::numeric INTO total FROM things WHERE id = tid;
    END IF;

    SELECT sum(due::numeric) INTO parties_due FROM parties WHERE thing_id = tid;
    SELECT sum(paid::numeric) INTO parties_paid FROM parties WHERE thing_id = tid;

    IF total IS NULL THEN
      IF parties_due != parties_paid THEN
        RAISE EXCEPTION 'since there is no total_due set, the sum of parties.due must equal the sum of parties.paid.';
      END IF;
    ELSE
      IF total != parties_paid THEN
        RAISE EXCEPTION 'if set, total_due must equal the sum of parties.paid.';
      END IF;

      IF parties_due > total THEN
        RAISE EXCEPTION 'sum of parties.due is more than total_due.';
      END IF;
    END IF;

    RETURN NULL;
  END;
$thing_totals$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER thing_totals AFTER INSERT OR UPDATE ON things
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE PROCEDURE thing_totals();

CREATE CONSTRAINT TRIGGER thing_totals AFTER INSERT OR UPDATE ON parties
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE PROCEDURE thing_totals();

CREATE FUNCTION default_asset(users) RETURNS text AS $$
  SELECT asset FROM (
    SELECT asset, count(*) AS c
    FROM users
    INNER JOIN parties ON parties.user_id = $1.id
    INNER JOIN things ON things.id = parties.thing_id
    GROUP BY asset
  )x
  ORDER BY c DESC
  LIMIT 1;
$$ LANGUAGE SQL;

CREATE FUNCTION publishable(things) RETURNS boolean AS $$
  SELECT coalesce(
    (
      SELECT total = confirmed FROM (
        SELECT
          count(*) AS total,
          sum(confirmed::int) AS confirmed
        FROM parties WHERE thing_id = $1.id
        GROUP BY thing_id
      )x
    ), false);
$$ LANGUAGE SQL;

CREATE FUNCTION nullable(t text) RETURNS text AS $$
  BEGIN
    IF t = '' THEN
      RETURN NULL;
    ELSE
      RETURN t;
    END IF;
  END;
$$
  LANGUAGE plpgsql
  IMMUTABLE
  RETURNS NULL ON NULL INPUT;

CREATE MATERIALIZED VIEW friends AS
  SELECT
    parties.user_id AS main,
    fid AS friend,
    count(*) AS score
  FROM parties
  INNER JOIN (
    SELECT parties.user_id AS fid, parties.thing_id AS tid
    FROM parties
  )x ON x.tid = parties.thing_id
  WHERE parties.user_id != fid
  GROUP BY (parties.user_id, fid);

CREATE INDEX friends_main ON friends (main);

CREATE FUNCTION refresh_friends() RETURNS TRIGGER AS $$
  BEGIN
    REFRESH MATERIALIZED VIEW friends;
    RETURN NULL;
  END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER refresh_friends AFTER INSERT OR UPDATE ON parties
  FOR EACH STATEMENT
  EXECUTE PROCEDURE refresh_friends();

-- drop everything

-- DROP TABLE users; -- BEWARE, DON'T DROP THIS
-- DROP TABLE parties;
-- DROP TABLE things;
DROP TRIGGER thing_totals ON parties;
DROP TRIGGER thing_totals ON things;
DROP FUNCTION thing_totals();
DROP FUNCTION publishable(things);
DROP FUNCTION default_asset(users);
DROP FUNCTION nullable(text);
DROP TRIGGER refresh_friends ON parties;
DROP FUNCTION refresh_friends();
DROP MATERIALIZED VIEW friends;
