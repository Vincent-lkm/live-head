-- Migration pour remplacer port par pod et location par redir

-- Table health_last
ALTER TABLE health_last ADD COLUMN pod TEXT DEFAULT 'unknown';
ALTER TABLE health_last ADD COLUMN redir TEXT;

-- Table health_history  
ALTER TABLE health_history ADD COLUMN pod TEXT DEFAULT 'unknown';
ALTER TABLE health_history ADD COLUMN redir TEXT;

-- On pourrait aussi supprimer les anciennes colonnes après migration
-- ALTER TABLE health_last DROP COLUMN port;
-- ALTER TABLE health_last DROP COLUMN location;
-- ALTER TABLE health_history DROP COLUMN port;
-- ALTER TABLE health_history DROP COLUMN location;