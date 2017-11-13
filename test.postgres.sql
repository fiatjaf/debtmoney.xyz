
BEGIN;
INSERT INTO things (id, created_by, total_due, asset) VALUES ('xyz', 'fiatjaf', '28', 'BRL');
INSERT INTO parties (thing_id, user_id, account_name, paid) VALUES ('xyz', 'fiatjaf', 'fiatjaf', '28');
COMMIT;

BEGIN;
INSERT INTO things (id, created_by, total_due, asset) VALUES ('ghj', 'fiatjaf', '28', 'BRL');
INSERT INTO parties (thing_id, user_id, account_name, paid) VALUES ('ghj', 'fiatjaf', 'fiatjaf', '26.50');
INSERT INTO parties (thing_id, account_name, paid) VALUES ('ghj', 'fulano', '13.50');
COMMIT;

BEGIN;
INSERT INTO things (id, created_by, total_due, asset) VALUES ('ghj', 'fiatjaf', '40', 'BRL');
INSERT INTO parties (thing_id, user_id, account_name, paid) VALUES ('ghj', 'fiatjaf', 'fiatjaf', '26.50');
INSERT INTO parties (thing_id, account_name, paid) VALUES ('ghj', 'fulano', '13.50');
COMMIT;

BEGIN;
INSERT INTO things (id, created_by, asset) VALUES ('ytr', 'fiatjaf', 'BRL');
INSERT INTO parties (thing_id, user_id, account_name, due, paid) VALUES ('ytr', 'fiatjaf', 'fiatjaf', '26.50', '16.5');
INSERT INTO parties (thing_id, account_name, due) VALUES ('ytr', 'fulano', '11');
INSERT INTO parties (thing_id, account_name, paid) VALUES ('ytr', 'beltrano', '20');
COMMIT;

BEGIN;
INSERT INTO things (id, created_by, asset) VALUES ('mno', 'fiatjaf', 'BRL');
INSERT INTO parties (thing_id, user_id, account_name, due, paid) VALUES ('mno', 'fiatjaf', 'fiatjaf', '26.50', '16.5');
INSERT INTO parties (thing_id, account_name, due) VALUES ('mno', 'fulano', '10');
INSERT INTO parties (thing_id, account_name, paid) VALUES ('mno', 'beltrano', '20');
COMMIT;

TABLE things;
TABLE parties;
