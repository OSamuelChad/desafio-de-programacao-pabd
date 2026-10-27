# Desafio de Programação 02 – Transações no PostgreSQL

Aluno: Samuel Chad 
Disciplina: PADB

## Ambiente

- PostgreSQL 16, banco `dvdrental` restaurado a partir do arquivo `dvdrental.tar`
- Cliente: `psql`

---

## Questão 1 – Cadastro de Cliente e Perfil

### O que eu fiz

Como o cliente precisa de um endereço (`address_id` é `NOT NULL` e tem chave estrangeira), dentro da mesma transação eu inseri primeiro o endereço e depois o cliente. Depois tentei inserir um segundo cliente com `first_name` nulo, que é obrigatório.

```sql
BEGIN;

INSERT INTO address (address, district, city_id, postal_code, phone)
VALUES ('Rua das Dunas, 100', 'Ponta Negra', 300, '59090000', '84999990000')
RETURNING address_id;

INSERT INTO customer (store_id, first_name, last_name, email, address_id, activebool, active)
VALUES (1, 'Samuel', 'Chad', 'samuel.chad@email.com', currval('address_address_id_seq'), TRUE, 1);

SELECT customer_id, first_name, last_name, address_id
FROM customer WHERE email = 'samuel.chad@email.com';

-- viola o NOT NULL de first_name
INSERT INTO customer (store_id, first_name, last_name, email, address_id, activebool, active)
VALUES (1, NULL, 'Teste', 'teste@email.com', currval('address_address_id_seq'), TRUE, 1);

SELECT 1;

ROLLBACK;
```

### Saída

```
BEGIN
 address_id
------------
        606
INSERT 0 1

 customer_id | first_name | last_name | address_id
-------------+------------+-----------+------------
         600 | Samuel     | Chad      |        606

ERROR:  null value in column "first_name" of relation "customer" violates not-null constraint
DETAIL:  Failing row contains (601, 1, null, Teste, teste@email.com, 606, t, 2026-10-27, ...).

SELECT 1;
ERROR:  current transaction is aborted, commands ignored until end of transaction block

ROLLBACK
```

Conferindo depois do `ROLLBACK`:

```sql
SELECT count(*) FROM customer WHERE email = 'samuel.chad@email.com';  -- 0
SELECT count(*) FROM address WHERE address_id > 605;                  -- 0
```

### Resposta

**O cliente do passo 1 não existe mais na tabela.** Dentro da transação ele aparecia (customer_id 600), mas depois do `ROLLBACK` a consulta retornou 0 linhas. O endereço que eu tinha criado junto também sumiu.

Duas coisas que deu para observar:

1. Depois do erro, a transação ficou em estado abortado. O `SELECT 1` seguinte já falhou com "current transaction is aborted". No PostgreSQL, depois de um erro só dá para finalizar com `ROLLBACK`.
2. O `ROLLBACK` não devolve os números da sequence. A `customer_customer_id_seq` ficou em 601, então o próximo cliente vai ser o 602 e os IDs 600 e 601 ficam sem uso.

**Por que o banco deve "esquecer" tudo se um detalhe falhar?** Por causa da atomicidade (o A do ACID). Um cadastro é uma operação só: ou o cliente é cadastrado completo, ou não é. Se o banco guardasse só uma parte, ficaria com dados pela metade, por exemplo um endereço sem dono ou um cliente incompleto que o sistema trata como válido. Com o rollback, o banco volta ao estado de antes e a pessoa pode tentar o cadastro de novo.

---

## Questão 2 – Gestão de Estoque e Suprimentos

### O que eu fiz

```sql
BEGIN;

INSERT INTO inventory (film_id, store_id) VALUES (1, 1) RETURNING inventory_id;

SAVEPOINT estoque_atualizado;

-- filme que não existe
INSERT INTO inventory (film_id, store_id) VALUES (9999, 1);

ROLLBACK TO SAVEPOINT estoque_atualizado;

INSERT INTO inventory (film_id, store_id) VALUES (2, 1) RETURNING inventory_id;

COMMIT;

SELECT inventory_id, film_id, store_id
FROM inventory WHERE inventory_id > 4581 ORDER BY inventory_id;
```

### Saída

```
BEGIN
 inventory_id
--------------
         4582
INSERT 0 1

SAVEPOINT

ERROR:  insert or update on table "inventory" violates foreign key constraint "inventory_film_id_fkey"
DETAIL:  Key (film_id)=(9999) is not present in table "film".

ROLLBACK

 inventory_id
--------------
         4584
INSERT 0 1

COMMIT

 inventory_id | film_id | store_id
--------------+---------+----------
         4582 |       1 |        1
         4584 |       2 |        1
(2 rows)
```

Observação: no começo eu tinha tentado o `film_id = 99999`, mas a coluna é `smallint` e o erro foi `smallint out of range`, que não é de chave estrangeira. Por isso usei 9999, que cabe em `smallint` e não existe na tabela `film` (o maior id é 1000).

### Resposta

**Depois do COMMIT a tabela ficou com os dois registros válidos** (4582, do filme 1, e 4584, do filme 2). A tentativa com o filme 9999 não entrou. Note que o 4583 sumiu da sequência: a sequence foi usada na inserção que falhou e não volta atrás.

**Vantagem do SAVEPOINT:** no PostgreSQL, qualquer erro deixa a transação inteira abortada. Sem o savepoint, a única saída seria um `ROLLBACK` total e eu perderia também a primeira inserção, que estava correta. Com o `ROLLBACK TO SAVEPOINT`, só o que veio depois do ponto salvo é desfeito, a transação volta a ficar utilizável e eu continuo de onde parei. Num lote grande de filmes, isso evita refazer tudo por causa de um item errado.

---

## Questão 3 – Concorrência no mesmo `inventory_id`

### Montagem

Duas conexões ao mesmo tempo, no nível de isolamento padrão (`READ COMMITTED`). Antes de cada cenário eu cadastrei e confirmei uma unidade nova na loja 1.

- Sessão A (gestor que transfere): `UPDATE inventory SET store_id = 2 WHERE inventory_id = X;`
- Sessão B (gestor que exclui): `DELETE FROM inventory WHERE inventory_id = X;`

Para controlar o momento exato de cada comando eu usei um script em Python com duas conexões (`q3_sim.py`, junto com este arquivo). O que cada sessão executa é o mesmo que seria digitado em dois terminais `psql`. Numa terceira conexão eu consultei `pg_stat_activity` para ver quem estava bloqueado.

A regra é: quem executa primeiro um comando sobre a linha adquire o bloqueio de linha, e a outra transação fica esperando até a primeira dar COMMIT ou ROLLBACK.

### Cenário 1 – Sessão A começa primeiro (inventory_id 4585)

| Passo | Sessão A (transferir) | Sessão B (excluir) |
|---|---|---|
| 1 | `BEGIN;` | |
| 2 | `UPDATE ... WHERE inventory_id = 4585;` → `UPDATE 1` (pega o lock) | |
| 3 | | `BEGIN;` |
| 4 | | `DELETE ... WHERE inventory_id = 4585;` → **fica travada** |
| 5 | (consulta em outra conexão) | `wait_event_type = Lock`, `wait_event = transactionid` |
| 6 | `COMMIT;` | |
| 7 | | destrava: `DELETE 1` |
| 8 | | `COMMIT;` |

Resultado final: a linha 4585 **não existe mais**. A transferência foi feita e depois a unidade foi excluída, porque o `DELETE` do B só filtra por `inventory_id` e a linha continuou casando depois do UPDATE.

**Variante com condição de guarda (4586):** se o B escrever `DELETE ... WHERE inventory_id = 4586 AND store_id = 1`, o resultado muda. Quando o B destrava, a linha já está na loja 2 e não casa mais com o filtro: `DELETE 0`. A linha fica no estado final `(4586, filme 1, loja 2)`. Ou seja, a unidade foi transferida e não foi apagada.

### Cenário 2 – Sessão B começa primeiro (inventory_id 4587)

| Passo | Sessão B (excluir) | Sessão A (transferir) |
|---|---|---|
| 1 | `BEGIN;` | |
| 2 | `DELETE ... WHERE inventory_id = 4587;` → `DELETE 1` (pega o lock) | |
| 3 | | `BEGIN;` |
| 4 | | `UPDATE ... WHERE inventory_id = 4587;` → **fica travada** |
| 5 | `COMMIT;` | |
| 6 | | destrava: `UPDATE 0` (a linha não existe mais, e não dá erro) |
| 7 | | `COMMIT;` |

Resultado final: a linha 4587 **não existe**. A transferência não aconteceu e o PostgreSQL não avisou com erro, só retornou `UPDATE 0`. Por isso a aplicação precisa conferir quantas linhas foram afetadas.

**Sub-caso (4588):** se o B der `ROLLBACK` em vez de `COMMIT`, o A destrava com `UPDATE 1` e a unidade termina na loja 2.

### Extra – REPEATABLE READ (4589)

Repeti o cenário 1 com as duas sessões em `REPEATABLE READ`. O B ficou travado do mesmo jeito, mas quando o A deu COMMIT o B recebeu:

```
ERROR:  could not serialize access due to concurrent update
```

e foi preciso dar `ROLLBACK`. A linha ficou `(4589, 1, 2)`. Neste nível o banco não reavalia a linha, ele manda a aplicação refazer a transação.

### Conclusão

O PostgreSQL não deixa as duas operações alterarem a linha ao mesmo tempo: a transação que chega primeiro fica com a linha e a outra espera. Por isso a ordem importa, e o resultado muda conforme quem começou primeiro:

- A primeiro: a unidade é transferida e depois excluída (a não ser que o DELETE tenha a condição `store_id = 1`).
- B primeiro: a unidade é excluída e a transferência retorna 0 linhas.

Para a locadora, o certo é cada gestor conferir o estado da linha antes de decidir, por exemplo com `SELECT ... FOR UPDATE` dentro da transação, ou usar condições no `WHERE` e verificar o número de linhas afetadas.
