pipeline {

    agent {
        kubernetes {
            cloud 'kubernetes'

            yaml '''
apiVersion: v1
kind: Pod

spec:
  automountServiceAccountToken: false

  containers:

    - name: dotnet
      image: mcr.microsoft.com/dotnet/sdk:10.0
      command:
        - sleep
      args:
        - 99d

    - name: ubuntu
      image: ubuntu:24.04
      command:
        - sleep
      args:
        - 99d
'''
        }
    }

    stages {

        stage('Pod Information') {
            steps {
                container('ubuntu') {
                    sh '''
                        echo "Running inside Kubernetes agent"
                        echo "Hostname:"
                        hostname

                        echo
                        echo "OS:"
                        cat /etc/os-release
                    '''
                }
            }
        }

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build') {
            steps {
                container('dotnet') {
                    sh '''
                        dotnet --info
                        dotnet restore
                        dotnet build -c Release --no-restore
                    '''
                }
            }
        }

        stage('Test') {
            steps {
                container('dotnet') {
                    sh '''
                        dotnet test -c Release --no-build
                    '''
                }
            }
        }
    }

    post {

        success {
            echo 'Build completed successfully.'
        }

        failure {
            echo 'Build failed.'
        }
    }
}