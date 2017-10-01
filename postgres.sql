CREATE TABLE users (
  id text PRIMARY KEY, -- will mirror a unified-users-database.herokuapp.com id.
  address text,
  seed text,

  CONSTRAINT id_validator CHECK (id ~ '[\w_]')
);

CREATE TYPE record_kind AS ENUM (
  'debt',
  'payment',
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
