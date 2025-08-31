-- Corriger la table sync_metadata_status_interne
USE stats;

-- Vérifier si la table existe et la créer si nécessaire
CREATE TABLE IF NOT EXISTS sync_metadata_status_interne (
    id INT PRIMARY KEY DEFAULT 1,
    last_sync_timestamp BIGINT,
    last_sync_date TIMESTAMP NULL,
    total_records_synced BIGINT DEFAULT 0,
    last_sync_status VARCHAR(50),
    last_error_message TEXT,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Si la table existe mais manque des colonnes, les ajouter
ALTER TABLE sync_metadata_status_interne 
    ADD COLUMN IF NOT EXISTS last_sync_status VARCHAR(50),
    ADD COLUMN IF NOT EXISTS last_error_message TEXT,
    ADD COLUMN IF NOT EXISTS last_sync_timestamp BIGINT,
    ADD COLUMN IF NOT EXISTS last_sync_date TIMESTAMP NULL,
    ADD COLUMN IF NOT EXISTS total_records_synced BIGINT DEFAULT 0;

-- Insérer la ligne initiale si elle n'existe pas
INSERT IGNORE INTO sync_metadata_status_interne (id, last_sync_status, total_records_synced) 
VALUES (1, 'ready', 0);

-- Vérifier que tout est OK
SELECT * FROM sync_metadata_status_interne;