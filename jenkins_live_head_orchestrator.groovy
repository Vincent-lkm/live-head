pipeline {
    agent any
    
    triggers {
        cron('H/30 * * * *')  // Toutes les 30 minutes
    }
    
    stages {
        stage('Lancer tous les Live Head') {
            parallel {
                stage('INFRA1') {
                    steps {
                        build job: 'Live Head INFRA1 VALIDE', wait: false
                    }
                }
                stage('INFRA2') {
                    steps {
                        build job: 'Live Head INFRA2 VALIDE', wait: false
                    }
                }
                stage('INFRA3') {
                    steps {
                        build job: 'Live Head INFRA3 VALIDE', wait: false
                    }
                }
                stage('INFRA4') {
                    steps {
                        build job: 'Live Head INFRA4 VALIDE', wait: false
                    }
                }
                stage('TIER1') {
                    steps {
                        build job: 'Live Head tier1 VALIDE', wait: false
                    }
                }
            }
        }
    }
    
    post {
        success {
            echo "✅ Tous les jobs Live Head lancés avec succès"
        }
        failure {
            echo "❌ Erreur lors du lancement des jobs Live Head"
        }
    }
}