-- Script de création des tables pour live_head_monitoring
-- Base de données pour stocker l'historique complet des scans

-- Table principale pour l'historique de monitoring
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
    INDEX idx_pod (pod),
    INDEX idx_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Table pour tracker les métadonnées de synchronisation
CREATE TABLE IF NOT EXISTS sync_metadata (
    id INT PRIMARY KEY DEFAULT 1,
    last_sync_timestamp BIGINT,
    last_sync_date TIMESTAMP NULL,
    total_records_synced BIGINT DEFAULT 0,
    last_sync_status VARCHAR(50),
    last_error_message TEXT,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CHECK (id = 1) -- Assure qu'il n'y a qu'une seule ligne
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Insérer la ligne initiale pour sync_metadata
INSERT IGNORE INTO sync_metadata (id, last_sync_status) 
VALUES (1, 'never_synced');

-- Vue pour avoir les derniers statuts par site
CREATE OR REPLACE VIEW latest_site_status AS
SELECT 
    s1.site,
    s1.status,
    s1.ms,
    s1.pod,
    s1.redir,
    s1.cross_domain,
    s1.timestamp,
    s1.created_at
FROM site_monitoring_history s1
INNER JOIN (
    SELECT site, MAX(timestamp) as max_timestamp
    FROM site_monitoring_history
    GROUP BY site
) s2 ON s1.site = s2.site AND s1.timestamp = s2.max_timestamp;

-- Vue pour les statistiques par jour
CREATE OR REPLACE VIEW daily_stats AS
SELECT 
    DATE(FROM_UNIXTIME(timestamp/1000)) as date,
    COUNT(DISTINCT site) as unique_sites,
    COUNT(*) as total_scans,
    SUM(CASE WHEN status = 200 THEN 1 ELSE 0 END) as status_200,
    SUM(CASE WHEN status >= 500 THEN 1 ELSE 0 END) as status_5xx,
    SUM(CASE WHEN status >= 300 AND status < 400 THEN 1 ELSE 0 END) as redirects,
    AVG(ms) as avg_response_time,
    MIN(ms) as min_response_time,
    MAX(ms) as max_response_time
FROM site_monitoring_history
GROUP BY DATE(FROM_UNIXTIME(timestamp/1000));

-- Vue pour les sites problématiques
CREATE OR REPLACE VIEW problematic_sites AS
SELECT 
    site,
    status,
    COUNT(*) as error_count,
    MAX(timestamp) as last_error,
    pod
FROM site_monitoring_history
WHERE status >= 500 OR cross_domain = 1
GROUP BY site, status, pod
ORDER BY error_count DESC;