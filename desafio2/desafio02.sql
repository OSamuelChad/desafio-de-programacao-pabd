-- Questão 1

BEGIN;

INSERT INTO address (address, district, city_id, postal_code, phone)
VALUES ('Rua das Dunas, 100', 'Ponta Negra', 300, '59090000', '84999990000')
RETURNING address_id;

INSERT INTO customer (store_id, first_name, last_name, email, address_id, activebool, active)
VALUES (1, 'Samuel', 'Chad', 'samuel.chad@email.com', currval('address_address_id_seq'), TRUE, 1);

SELECT customer_id, first_name, last_name, address_id
FROM customer
WHERE email = 'samuel.chad@email.com';

-- first_name é NOT NULL, então esse insert falha
INSERT INTO customer (store_id, first_name, last_name, email, address_id, activebool, active)
VALUES (1, NULL, 'Teste', 'teste@email.com', currval('address_address_id_seq'), TRUE, 1);

ROLLBACK;

SELECT count(*) FROM customer WHERE email = 'samuel.chad@email.com';
SELECT count(*) FROM address WHERE address_id > 605;

-- Resposta: não, o cliente não existe mais. Dentro da transação ele aparecia,
-- mas depois do ROLLBACK a consulta volta 0 linhas (o endereço também sumiu).
-- O banco desfaz tudo por causa da atomicidade: o cadastro é uma operação só,
-- ou fica completo ou não fica. Se guardasse só uma parte ia sobrar dado
-- solto, tipo endereço sem cliente ou cliente incompleto.

-- Questão 2

BEGIN;

INSERT INTO inventory (film_id, store_id) VALUES (1, 1) RETURNING inventory_id;

SAVEPOINT estoque_atualizado;

-- filme 9999 não existe, vai dar erro de chave estrangeira
INSERT INTO inventory (film_id, store_id) VALUES (9999, 1);

ROLLBACK TO SAVEPOINT estoque_atualizado;

INSERT INTO inventory (film_id, store_id) VALUES (2, 1) RETURNING inventory_id;

COMMIT;

SELECT inventory_id, film_id, store_id
FROM inventory
WHERE inventory_id > 4581
ORDER BY inventory_id;

-- Resposta: a tabela fica com os dois registros válidos (filme 1 e filme 2).
-- O do filme 9999 nunca entra.
-- Sem o SAVEPOINT, depois do erro a transação fica abortada e só dá pra
-- fazer ROLLBACK de tudo, perdendo também a primeira inserção que estava certa.
-- Com o savepoint só o trecho com erro é desfeito e o resto do lote continua.

-- Questão 3
-- Rodar em dois terminais psql, seguindo a ordem dos passos.

-- Preparação (qualquer terminal): cria duas unidades novas na loja 1,
-- uma para cada cenário. Anotar os dois ids que voltarem.
INSERT INTO inventory (film_id, store_id) VALUES (1, 1), (1, 1) RETURNING inventory_id;

-- nos dois terminais, trocar pelos ids retornados
\set id1 4585
\set id2 4586


-- ---------- Cenário 1: sessão A começa primeiro ----------

-- passo 1 (terminal A)
BEGIN;
UPDATE inventory SET store_id = 2 WHERE inventory_id = :id1;

-- passo 2 (terminal B): fica travado esperando o A
BEGIN;
DELETE FROM inventory WHERE inventory_id = :id1;

-- passo 3 (terminal A)
COMMIT;

-- passo 4 (terminal B): o delete destrava e retorna DELETE 1
COMMIT;

SELECT * FROM inventory WHERE inventory_id = :id1;
-- resultado: 0 linhas, a unidade foi transferida e depois excluída.
-- Se o delete tivesse AND store_id = 1, retornaria DELETE 0 e a unidade
-- ficaria na loja 2.


-- ---------- Cenário 2: sessão B começa primeiro ----------

-- passo 1 (terminal B)
BEGIN;
DELETE FROM inventory WHERE inventory_id = :id2;

-- passo 2 (terminal A): fica travado esperando o B
BEGIN;
UPDATE inventory SET store_id = 2 WHERE inventory_id = :id2;

-- passo 3 (terminal B)
COMMIT;

-- passo 4 (terminal A): o update destrava e retorna UPDATE 0
COMMIT;

SELECT * FROM inventory WHERE inventory_id = :id2;
-- resultado: 0 linhas, a unidade foi excluída e a transferência não
-- aconteceu (UPDATE 0, sem erro). Se o B desse ROLLBACK no passo 3, o
-- update do A retornaria UPDATE 1.


-- Para ver o bloqueio, em um terceiro terminal enquanto uma sessão está travada:
SELECT pid, state, wait_event_type, wait_event, query
FROM pg_stat_activity
WHERE datname = 'dvdrental' AND wait_event_type = 'Lock';
