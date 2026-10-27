BEGIN;

INSERT INTO address (address, district, city_id, postal_code, phone)
VALUES ('Rua das Dunas, 100', 'Ponta Negra', 300, '59090000', '84999990000')
RETURNING address_id;          -- suponha que retornou 606

INSERT INTO customer (store_id, first_name, last_name, email, address_id, activebool, active)
VALUES (1, 'Samuel', 'Chad', 'samuel.chad@email.com', 606, TRUE, 1);

SELECT customer_id, first_name FROM customer WHERE email = 'samuel.chad@email.com';

INSERT INTO customer (store_id, first_name, last_name, email, address_id, activebool, active)
VALUES (1, NULL, 'Teste', 'teste@email.com', 606, TRUE, 1);
-- ERROR: null value in column "first_name" of relation "customer"
--        violates not-null constraint

transação agora está em estado "aborted"
SELECT 1;
-- ERROR: current transaction is aborted, commands ignored until end of transaction block

ROLLBACK;

-- Verificação
SELECT * FROM customer WHERE email = 'samuel.chad@email.com';   -- 0 linhas
SELECT * FROM address  WHERE address_id = 606;                  -- 0 linhas