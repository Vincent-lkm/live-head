#!/usr/bin/env python3
"""
Script de synchronisation D1 Cloudflare vers MySQL
Récupère l'historique complet depuis l'API et l'insère dans MySQL
"""

import requests
import mysql.connector
from mysql.connector import Error
import json
import time
from datetime import datetime
import sys
import argparse

# Configuration
CLOUDFLARE_API_URL = "https://live-head.restless-dust-dcc3.workers.dev/dump_last"
MYSQL_CONFIG = {
    'host': '138.201.84.171',
    'port': 3306,
    'user': 'vins',
    'password': 'LiveHead2024!Sync',
    'database': 'stats'
}

class D1ToMySQLSync:
    def __init__(self, dry_run=False):
        self.dry_run = dry_run
        self.connection = None
        self.cursor = None
        self.stats = {
            'total_fetched': 0,
            'new_records': 0,
            'duplicates': 0,
            'errors': 0
        }
    
    def connect_mysql(self):
        """Établit la connexion MySQL"""
        try:
            self.connection = mysql.connector.connect(**MYSQL_CONFIG)
            self.cursor = self.connection.cursor(dictionary=True)
            print(f"✅ Connecté à MySQL: {MYSQL_CONFIG['host']}")
            return True
        except Error as e:
            print(f"❌ Erreur connexion MySQL: {e}")
            return False
    
    def fetch_from_cloudflare(self, limit=5000, offset=0):
        """Récupère les données depuis l'API Cloudflare"""
        try:
            url = f"{CLOUDFLARE_API_URL}?limit={limit}&offset={offset}"
            print(f"📡 Récupération depuis Cloudflare (limit={limit}, offset={offset})...")
            
            response = requests.get(url, timeout=30)
            response.raise_for_status()
            
            data = response.json()
            if data.get('ok'):
                return data.get('data', []), data.get('count', 0)
            else:
                print(f"❌ Erreur API: {data}")
                return [], 0
                
        except requests.RequestException as e:
            print(f"❌ Erreur lors de la récupération: {e}")
            return [], 0
    
    def get_existing_timestamps(self, sites):
        """Récupère les timestamps existants pour éviter les doublons"""
        if not sites:
            return set()
        
        site_list = "','".join(sites)
        query = f"""
            SELECT CONCAT(site, '_', timestamp) as site_timestamp
            FROM site_status_interne
            WHERE site IN ('{site_list}')
        """
        
        try:
            self.cursor.execute(query)
            results = self.cursor.fetchall()
            return {row['site_timestamp'] for row in results}
        except Error as e:
            print(f"❌ Erreur récupération timestamps: {e}")
            return set()
    
    def insert_records(self, records):
        """Insère les nouveaux enregistrements dans MySQL"""
        if not records:
            return
        
        # Récupérer les sites uniques
        sites = list(set(r['site'] for r in records))
        existing = self.get_existing_timestamps(sites)
        
        # Préparer les données à insérer
        new_records = []
        for record in records:
            # Créer l'identifiant unique
            site_timestamp = f"{record['site']}_{record.get('time', 0)}"
            
            if site_timestamp not in existing:
                new_records.append((
                    record['site'],
                    record.get('status', 0),
                    record.get('ms', 0),
                    record.get('pod', 'unknown'),
                    record.get('redir'),
                    1 if record.get('cross-domain') else 0,
                    record.get('time', 0)
                ))
            else:
                self.stats['duplicates'] += 1
        
        if new_records:
            if self.dry_run:
                print(f"🔍 [DRY RUN] {len(new_records)} nouveaux enregistrements à insérer")
                return
            
            insert_query = """
                INSERT INTO site_status_interne 
                (site, status, ms, pod, redir, cross_domain, timestamp)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
            """
            
            try:
                self.cursor.executemany(insert_query, new_records)
                self.connection.commit()
                self.stats['new_records'] += len(new_records)
                print(f"✅ {len(new_records)} nouveaux enregistrements insérés")
            except Error as e:
                print(f"❌ Erreur insertion: {e}")
                self.stats['errors'] += len(new_records)
                self.connection.rollback()
    
    def update_sync_metadata(self):
        """Met à jour les métadonnées de synchronisation"""
        if self.dry_run:
            print("🔍 [DRY RUN] Mise à jour des métadonnées")
            return
        
        try:
            query = """
                UPDATE sync_metadata_status_interne 
                SET last_sync_timestamp = %s,
                    last_sync_date = NOW(),
                    total_records_synced = total_records_synced + %s,
                    last_sync_status = %s,
                    last_error_message = %s
                WHERE id = 1
            """
            
            status = 'success' if self.stats['errors'] == 0 else 'partial'
            error_msg = None if self.stats['errors'] == 0 else f"{self.stats['errors']} erreurs"
            
            self.cursor.execute(query, (
                int(time.time() * 1000),
                self.stats['new_records'],
                status,
                error_msg
            ))
            self.connection.commit()
            print("✅ Métadonnées de synchronisation mises à jour")
            
        except Error as e:
            print(f"❌ Erreur mise à jour métadonnées: {e}")
    
    def get_stats(self):
        """Récupère les statistiques de la base"""
        try:
            # Nombre total d'enregistrements
            self.cursor.execute("SELECT COUNT(*) as total FROM site_status_interne")
            total = self.cursor.fetchone()['total']
            
            # Nombre de sites uniques
            self.cursor.execute("SELECT COUNT(DISTINCT site) as sites FROM site_status_interne")
            sites = self.cursor.fetchone()['sites']
            
            # Dernière synchronisation
            self.cursor.execute("SELECT last_sync_date, total_records_synced FROM sync_metadata_status_interne WHERE id = 1")
            sync_info = self.cursor.fetchone()
            
            print("\n📊 Statistiques de la base:")
            print(f"   - Total enregistrements: {total:,}")
            print(f"   - Sites uniques: {sites:,}")
            if sync_info['last_sync_date']:
                print(f"   - Dernière sync: {sync_info['last_sync_date']}")
                print(f"   - Total synchronisé: {sync_info['total_records_synced']:,}")
                
        except Error as e:
            print(f"❌ Erreur récupération stats: {e}")
    
    def sync(self, full_sync=False):
        """Lance la synchronisation"""
        print("🚀 Démarrage de la synchronisation D1 → MySQL")
        print(f"   Mode: {'COMPLET' if full_sync else 'INCREMENTAL'}")
        if self.dry_run:
            print("   🔍 MODE DRY RUN - Aucune modification ne sera effectuée")
        
        if not self.connect_mysql():
            return False
        
        try:
            offset = 0
            limit = 5000
            
            while True:
                # Récupérer les données
                records, total = self.fetch_from_cloudflare(limit, offset)
                
                if not records:
                    break
                
                self.stats['total_fetched'] += len(records)
                print(f"📦 Batch {offset//limit + 1}: {len(records)} enregistrements")
                
                # Insérer les enregistrements
                self.insert_records(records)
                
                # Si on a récupéré moins que la limite, on a fini
                if len(records) < limit:
                    break
                
                offset += limit
                
                # Pause pour ne pas surcharger l'API
                time.sleep(0.5)
            
            # Mettre à jour les métadonnées
            self.update_sync_metadata()
            
            # Afficher les statistiques
            print("\n✅ Synchronisation terminée!")
            print(f"   - Total récupéré: {self.stats['total_fetched']:,}")
            print(f"   - Nouveaux enregistrements: {self.stats['new_records']:,}")
            print(f"   - Doublons ignorés: {self.stats['duplicates']:,}")
            print(f"   - Erreurs: {self.stats['errors']:,}")
            
            # Afficher les stats de la base
            self.get_stats()
            
            return True
            
        except Exception as e:
            print(f"❌ Erreur durant la synchronisation: {e}")
            return False
            
        finally:
            if self.cursor:
                self.cursor.close()
            if self.connection:
                self.connection.close()
                print("\n🔌 Connexion MySQL fermée")

def main():
    parser = argparse.ArgumentParser(description='Synchronise D1 Cloudflare vers MySQL')
    parser.add_argument('--dry-run', action='store_true', help='Mode test sans insertion')
    parser.add_argument('--full', action='store_true', help='Synchronisation complète')
    
    args = parser.parse_args()
    
    syncer = D1ToMySQLSync(dry_run=args.dry_run)
    success = syncer.sync(full_sync=args.full)
    
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()