CREATE TABLE users (
  id text PRIMARY KEY, -- will mirror a unified-users-database.herokuapp.com id.
  address text,
  seed text
);

CREATE TABLE records (
  id serial PRIMARY KEY,
  created_at timestamp DEFAULT now(),
  data jsonb NOT NULL,

  CONSTRAINT required_keys CHECK (data ?& array['txns', 'cred', 'debs', 'asset', 'amt', 'ok']),
  CONSTRAINT transactions_type CHECK (jsonb_typeof(data->'txns') = 'array'),
  CONSTRAINT creditor_type CHECK (jsonb_typeof(data->'cred') = 'string'),
  CONSTRAINT amount_type CHECK (jsonb_typeof(data->'amt') = 'number'),
  CONSTRAINT asset_type CHECK (jsonb_typeof(data->'asset') = 'string'),
  CONSTRAINT debtor_type CHECK (jsonb_typeof(data->'debs') = 'array'),
  CONSTRAINT debtor_len CHECK (jsonb_array_length(data->'debs') > 0),
  CONSTRAINT confirmed_type CHECK (jsonb_typeof(data->'ok') = 'object')
);
