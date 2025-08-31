-- Supprimer les anciennes tables
DROP TABLE IF EXISTS health_last;
DROP TABLE IF EXISTS health_history;

-- Recréer health_last avec les bonnes colonnes
CREATE TABLE health_last (
    site TEXT PRIMARY KEY,
    status INTEGER NOT NULL,
    ms INTEGER NOT NULL,
    pod TEXT DEFAULT 'unknown',
    redir TEXT,
    cross INTEGER DEFAULT 0,
    ts INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);

-- Recréer health_history avec les bonnes colonnes
CREATE TABLE health_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    site TEXT NOT NULL,
    status INTEGER NOT NULL,
    ms INTEGER NOT NULL,
    pod TEXT DEFAULT 'unknown',
    redir TEXT,
    cross INTEGER DEFAULT 0,
    ts INTEGER NOT NULL
);

-- Index pour améliorer les performances
CREATE INDEX idx_health_last_ts ON health_last(ts);
CREATE INDEX idx_health_last_status ON health_last(status);
CREATE INDEX idx_health_history_site_ts ON health_history(site, ts);
CREATE INDEX idx_health_history_ts ON health_history(ts);