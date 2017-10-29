CREATE TABLE users (
  id text PRIMARY KEY, -- will mirror a unified-users-database.herokuapp.com id.
  address text,
  seed text,

  CONSTRAINT id_size CHECK (char_length(id) < 22),
  CONSTRAINT id_validator CHECK (id ~ '^[a-z][\w_]+$')
);

CREATE TYPE record_kind AS ENUM (
  'debt', -- a simple declaration of a debt contracted in the real world
  'payment', -- same as above, but the meaning is slightly different: someone
             -- has paid something for another.
             -- this applies in most cases where 'debt' can also be applied,
             -- however, if can also be used in multihop payments, for example:
             -- B has paid something to C for A: this creates the equivalent of a
             -- debt from A to B (but that should happen automatically, through
             -- token exchange).
  'bill-split'
);

CREATE TABLE records (
  id serial PRIMARY KEY,
  created_at timestamp DEFAULT now(),
  record_date timestamp DEFAULT Now(),
  kind record_kind NOT NULL,
  asset text NOT NULL,
  description jsonb NOT NULL, -- this describes what actually happened, like
                              -- john, monica and pablo went to a bar, john paid
                              -- 20, monica paid 22.50 and pablo 15. each should
                              -- have paid x, except for pablo which should have
                              -- paid only 14.
  confirmed text[], -- the list of people who have confirmed this. when it is full
                    -- the transactions are published.
  transactions text[] DEFAULT '{}'::text[]
);

CREATE INDEX ON records ((description->>'from'));
CREATE INDEX ON records ((description->>'to'));
