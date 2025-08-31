-- Création de la base de données et des tables pour le monitoring
CREATE DATABASE IF NOT EXISTS site_status_interne 
    CHARACTER SET utf8mb4 
    COLLATE utf8mb4_unicode_ci;

USE site_status_interne;

-- Table principale pour l'historique
CREATE TABLE IF NOT EXISTS site_monitoring_history (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    site VARCHAR(255) NOT NULL,
    status INT NOT NULL,
    ms INT NOT NULL,
    pod VARCHAR(100) DEFAULT 'unknown',
    redir TEXT,
    cross_domain TINYINT DEFAULT 0,
    timestamp BIGINT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY unique_site_timestamp (site, timestamp),
    INDEX idx_site (site),
    INDEX idx_timestamp (timestamp),
    INDEX idx_status (status),
    INDEX idx_pod (pod)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Table pour les métadonnées de synchronisation
CREATE TABLE IF NOT EXISTS sync_metadata_status_interne (
    id INT PRIMARY KEY DEFAULT 1,
    last_sync_timestamp BIGINT,
    last_sync_date TIMESTAMP NULL,
    total_records_synced BIGINT DEFAULT 0,
    last_sync_status VARCHAR(50),
    last_error_message TEXT,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CHECK (id = 1)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Initialiser la ligne de métadonnées
INSERT IGNORE INTO sync_metadata_status_interne (id, last_sync_status) 
VALUES (1, 'never_synced');

-- Afficher les tables créées
SHOW TABLES;

-- Vérifier la structure
DESCRIBE site_monitoring_history;
DESCRIBE sync_metadata_status_interne;