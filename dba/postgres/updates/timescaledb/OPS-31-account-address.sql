ALTER TABLE solarbill.bill_address ADD COLUMN user_id BIGINT;

UPDATE solarbill.bill_address
SET user_id = bill_account.user_id
FROM solarbill.bill_account
WHERE bill_address.id = solarbill.bill_account.addr_id;

UPDATE solarbill.bill_address
SET user_id = -1
WHERE user_id IS NULL;

ALTER TABLE solarbill.bill_address ALTER COLUMN user_id SET NOT NULL;

CREATE INDEX IF NOT EXISTS bill_address_user_idx ON solarbill.bill_address (user_id, created DESC);

