-- Unidade recém-cadastrada e já confirmada (precisa estar commitada para as duas sessões a verem)
INSERT INTO inventory (film_id, store_id) VALUES (1, 1) RETURNING inventory_id;
-- suponha inventory_id = 4582, na loja 1