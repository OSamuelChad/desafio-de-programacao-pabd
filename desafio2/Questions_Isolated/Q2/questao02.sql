BEGIN;

INSERT INTO inventory (film_id, store_id) VALUES (1, 1);

SAVEPOINT estoque_atualizado;

INSERT INTO inventory (film_id, store_id) VALUES (99999, 1);
-- ERROR: insert or update on table "inventory" violates foreign key
--        constraint "inventory_film_id_fkey"
-- DETAIL: Key (film_id)=(99999) is not present in table "film".

Desfaz só o que veio depois do savepoint; a 1ª inserção continua viva
ROLLBACK TO SAVEPOINT estoque_atualizado;

-- Inserção válida e confirmação
INSERT INTO inventory (film_id, store_id) VALUES (2, 1);

COMMIT;

-- Verificação (as 2 últimas linhas)
SELECT * FROM inventory ORDER BY inventory_id DESC LIMIT 2;