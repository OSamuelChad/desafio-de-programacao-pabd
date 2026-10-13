-- Questão 1
DROP MATERIALIZED VIEW IF EXISTS mv_driver_season_summary;
DROP INDEX IF EXISTS ux_mv_driver_season_summary;

CREATE MATERIALIZED VIEW mv_driver_season_summary AS
SELECT
    r.year,
    rd.driver_id,
    d.full_name AS driver_name,
    COUNT(*) AS total_races,
    COUNT(CASE WHEN rd.position_number = 1 THEN 1 END) AS wins,
    COUNT(CASE WHEN rd.position_number <= 3 THEN 1 END) AS podiums,
    COUNT(CASE WHEN rd.race_reason_retired IS NOT NULL THEN 1 END) AS dnfs,
    COALESCE(SUM(rd.race_points), 0) AS total_points
FROM race_data rd
JOIN race r ON r.id = rd.race_id
JOIN driver d ON d.id = rd.driver_id
WHERE rd.type = 'RACE_RESULT'
GROUP BY r.year, rd.driver_id, d.full_name;

CREATE UNIQUE INDEX ux_mv_driver_season_summary
    ON mv_driver_season_summary (year, driver_id);

REFRESH MATERIALIZED VIEW CONCURRENTLY mv_driver_season_summary;

-- Questão 2
DROP TABLE IF EXISTS points_adjustment_audit;
CREATE TABLE points_adjustment_audit (
    id SERIAL PRIMARY KEY,
    year INT NOT NULL,
    driver_id VARCHAR(100) NOT NULL,
    old_points DECIMAL(8,2),
    new_points DECIMAL(8,2),
    changed_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION audit_points_adjustment()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.points IS DISTINCT FROM OLD.points THEN
        INSERT INTO points_adjustment_audit (year, driver_id, old_points, new_points)
        VALUES (NEW.year, NEW.driver_id, OLD.points, NEW.points);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_points_adjustment_audit ON season_driver_standing;
CREATE TRIGGER trg_points_adjustment_audit
AFTER UPDATE ON season_driver_standing
FOR EACH ROW
WHEN (OLD.points IS DISTINCT FROM NEW.points)
EXECUTE FUNCTION audit_points_adjustment();

-- Questão 3
CREATE OR REPLACE FUNCTION prevent_driver_delete_with_race_data()
RETURNS TRIGGER AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM race_data rd
        WHERE rd.driver_id = OLD.id
    ) THEN
        RAISE EXCEPTION 'Não é possível excluir o piloto % porque ele possui registros na race_data.', OLD.full_name;
    END IF;

    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_prevent_driver_delete_with_race_data ON driver;
CREATE TRIGGER trg_prevent_driver_delete_with_race_data
BEFORE DELETE ON driver
FOR EACH ROW
EXECUTE FUNCTION prevent_driver_delete_with_race_data();
