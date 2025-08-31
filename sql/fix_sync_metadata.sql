-- Corriger la table sync_metadata_status_interne
USE stats;

-- Ajouter les colonnes manquantes si elles n'existent pas
ALTER TABLE sync_metadata_status_interne 
ADD COLUMN IF NOT EXISTS last_sync_status VARCHAR(50),
ADD COLUMN IF NOT EXISTS last_error_message TEXT;

-- Initialiser avec une valeur par défaut
UPDATE sync_metadata_status_interne 
SET last_sync_status = 'synced' 
WHERE id = 1;