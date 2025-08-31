pipeline {
    agent any
    
    triggers {
        cron('H/30 * * * *')  // Toutes les 30 minutes
    }
    
    stages {
        stage('Live Head INFRA1') {
            steps {
                build job: 'Live Head INFRA1 VALIDE', wait: true
            }
        }
        stage('Live Head INFRA2') {
            steps {
                sleep(time: 30, unit: 'SECONDS')  // Petit délai
                build job: 'Live Head INFRA2 VALIDE', wait: true
            }
        }
        stage('Live Head INFRA3') {
            steps {
                sleep(time: 30, unit: 'SECONDS')
                build job: 'Live Head INFRA3 VALIDE', wait: true
            }
        }
        stage('Live Head INFRA4') {
            steps {
                sleep(time: 30, unit: 'SECONDS')
                build job: 'Live Head INFRA4 VALIDE', wait: true
            }
        }
        stage('Live Head tier1') {
            steps {
                sleep(time: 30, unit: 'SECONDS')
                build job: 'Live Head tier1 VALIDE', wait: true
            }
        }
    }
}