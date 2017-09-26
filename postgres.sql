CREATE TABLE accounts (
  name text,
  source text,
  public text,
  secret text,

  PRIMARY KEY (name, source)
);
