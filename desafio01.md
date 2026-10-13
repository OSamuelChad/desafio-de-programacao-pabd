# DESAFIO DE PROGRAMAÇÃO 1

Vocês foram contratados como **Engenheiros de Dados Sênior** pela *F1 Analytics Corp*, uma startup que fornece dados em tempo real para as equipes de Fórmula 1!

O banco de dados que usaremos é o famoso **F1DB**, adaptado para os padrões do PostgreSQL. O volume de dados históricos é massivo (décadas de corridas), e as regras de negócio da FIA (Federação Internacional de Automobilismo) são rigorosas.

---

## Visão geral do banco de dados F1DB

Antes de começar, entendam as tabelas centrais do nosso desafio:

| Tabela | Papel |
|---|---|
| `driver` | Pilotos com estatísticas de carreira (totais de vitórias, pódios, pontos...) |
| `constructor` | Construtores/equipes |
| `race` | Corridas (ano, rodada, data, circuito, GP) |
| `race_data` | TODOS os dados de treinos, classificação, corrida, pit stops, etc. A coluna `type` define o tipo de registro |
| `season_driver` | Estatísticas agregadas por piloto por temporada |
| `season_driver_standing` | Classificação do campeonato por piloto |
| `circuit` / `grand_prix` | Circuitos e GPs |

> **OBS.:** A tabela `race_data` é o coração do banco. A coluna `type` (ex: `'RACE_RESULT'`, `'QUALIFYING_RESULT'`, `'FASTEST_LAP'`) determina quais colunas são relevantes em cada linha. As views já existentes no DDL (como `race_result`, `qualifying_result`) apenas filtram essa tabela por tipo.

---

## Questão 1 - Resumo por piloto/temporada

O painel analítico precisa de um resumo rápido por piloto/temporada sem consultar a gigantesca `race_data` a cada acesso. Crie uma materialized view `mv_driver_season_summary` que agregue os resultados de corrida (`type = 'RACE_RESULT'`) mostrando: ano, piloto, total de corridas, vitórias, pódios, abandonos (DNFs) e total de pontos. Inclua um índice único e o comando de `REFRESH CONCURRENTLY`. Para testar, exibir o resumo das 10 últimas temporadas de Ayrton Senna.

> **OBS.:** Utilize COUNT Condicional - `COUNT(CASE WHEN condicao THEN 1 END)` - para realizar a filtragem de vitórias (`position_number = 1`), pódios (`position_number <= 3`) e abandonos (`race_reason_retired IS NOT NULL`);

---

## Questão 2 - Auditoria de pontos do campeonato

Pontos do campeonato podem ser ajustados após penalizações. Crie uma tabela de auditoria `points_adjustment_audit` e uma trigger na tabela `season_driver_standing` que registre alterações de pontos **apenas quando houver mudança real**. Para testar, tente incrementar a quantidade de pontos da temporada 1993 de Ayrton Senna em 100. Verifique se a tabela `points_adjustment_audit` foi atualizada.

```sql
DROP TABLE IF EXISTS points_adjustment_audit;
CREATE TABLE points_adjustment_audit (
    id         SERIAL PRIMARY KEY,
    year       INT NOT NULL,
    driver_id  VARCHAR(100) NOT NULL,
    old_points DECIMAL(8,2),
    new_points DECIMAL(8,2),
    changed_at TIMESTAMPTZ DEFAULT NOW(),
);
```

## Questão 3 - Impedir exclusão de piloto com histórico

Crie uma trigger para impedir a exclusão de um piloto da tabela `driver` caso existam registros na `race_data` vinculados a ele. Lance uma exceção com o nome do piloto. Para testar, tente excluir Ayrton Senna da tabela `driver`. Logo após, exclua algum piloto sem registros em `race_data`.