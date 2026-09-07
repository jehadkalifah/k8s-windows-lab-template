pipeline {
    agent { label 'docker-dotnet' }

    options {
        timestamps()
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '20'))
        skipDefaultCheckout(true)
    }

    parameters {
        booleanParam(name: 'ENABLE_SONAR', defaultValue: true, description: 'Run SonarQube analysis and Quality Gate.')
        booleanParam(name: 'ENABLE_TRIVY', defaultValue: true, description: 'Scan the built image with Trivy.')
        booleanParam(name: 'PUSH_IMAGE', defaultValue: true, description: 'Push immutable image tag to OCIR.')
        string(name: 'GITOPS_REPO_URL', defaultValue: '', description: 'HTTPS GitOps repository URL. Empty = CI only.')
    }

    environment {
        OCIR_REGISTRY = 'jed.ocir.io'
        OCIR_NAMESPACE = 'CHANGE_ME'
        IMAGE_NAME = 'sample-api'
        OCIR_CREDENTIAL_ID = 'ocir-credentials'
        GITOPS_CREDENTIAL_ID = 'gitops-credentials'
        SONARQUBE_SERVER = 'SonarQubeServer'
        SONAR_PROJECT_KEY = 'sample-api'
    }

    stages {
        stage('Checkout') {
            steps { checkout scm }
        }

        stage('Metadata') {
            steps {
                script {
                    def shortSha = sh(script: 'git rev-parse --short=8 HEAD', returnStdout: true).trim()
                    def safeBranch = env.BRANCH_NAME.toLowerCase().replaceAll('[^a-z0-9._-]', '-')
                    def envMap = ['development':'dev', 'qa':'qa', 'preprod':'preprod', 'main':'prod']
                    env.DEPLOY_ENV = envMap.get(env.BRANCH_NAME, '')
                    env.IMAGE_TAG = "${safeBranch}-${env.BUILD_NUMBER}-${shortSha}"
                    env.FULL_IMAGE = "${env.OCIR_REGISTRY}/${env.OCIR_NAMESPACE}/${env.IMAGE_NAME}:${env.IMAGE_TAG}"
                    echo "Branch: ${env.BRANCH_NAME}"
                    echo "Environment: ${env.DEPLOY_ENV ?: 'CI only'}"
                    echo "Image: ${env.FULL_IMAGE}"
                }
            }
        }

        stage('Restore') {
            steps { sh 'dotnet restore SampleCiCd.slnx' }
        }

        stage('SonarQube Begin') {
            when { expression { params.ENABLE_SONAR } }
            steps {
                withSonarQubeEnv("${SONARQUBE_SERVER}") {
                    sh '''
                        dotnet tool restore
                        dotnet sonarscanner begin /k:"${SONAR_PROJECT_KEY}" /d:sonar.token="${SONAR_AUTH_TOKEN}"
                    '''
                }
            }
        }

        stage('Build') {
            steps { sh 'dotnet build SampleCiCd.slnx -c Release --no-restore' }
        }

        stage('Unit Tests') {
            steps {
                sh '''
                    dotnet test tests/SampleApi.Tests/SampleApi.Tests.csproj \
                      -c Release --no-build \
                      --logger "trx;LogFileName=test-results.trx"
                '''
            }
            post {
                always { archiveArtifacts artifacts: '**/TestResults/*.trx', allowEmptyArchive: true }
            }
        }

        stage('SonarQube End') {
            when { expression { params.ENABLE_SONAR } }
            steps {
                withSonarQubeEnv("${SONARQUBE_SERVER}") {
                    sh 'dotnet sonarscanner end /d:sonar.token="${SONAR_AUTH_TOKEN}"'
                }
            }
        }

        stage('Quality Gate') {
            when { expression { params.ENABLE_SONAR } }
            steps {
                timeout(time: 10, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        stage('Docker Build') {
            steps {
                sh '''
                    test "${OCIR_NAMESPACE}" != "CHANGE_ME" || { echo "Set OCIR_NAMESPACE in Jenkinsfile."; exit 1; }
                    docker build -t "${FULL_IMAGE}" .
                '''
            }
        }

        stage('Trivy Image Scan') {
            when { expression { params.ENABLE_TRIVY } }
            steps {
                sh '''
                    trivy image --exit-code 1 --severity HIGH,CRITICAL --ignore-unfixed "${FULL_IMAGE}"
                '''
            }
        }

        stage('Push to OCIR') {
            when { expression { params.PUSH_IMAGE } }
            steps {
                withCredentials([usernamePassword(credentialsId: "${OCIR_CREDENTIAL_ID}", usernameVariable: 'OCIR_USER', passwordVariable: 'OCIR_TOKEN')]) {
                    sh '''
                        printf '%s' "${OCIR_TOKEN}" | docker login "${OCIR_REGISTRY}" --username "${OCIR_USER}" --password-stdin
                        docker push "${FULL_IMAGE}"
                        docker logout "${OCIR_REGISTRY}" || true
                    '''
                }
            }
        }

        stage('GitOps Update') {
            when {
                allOf {
                    expression { params.PUSH_IMAGE }
                    expression { env.DEPLOY_ENV?.trim() }
                    expression { params.GITOPS_REPO_URL?.trim() }
                }
            }
            steps {
                withCredentials([usernamePassword(credentialsId: "${GITOPS_CREDENTIAL_ID}", usernameVariable: 'GIT_USER', passwordVariable: 'GIT_TOKEN')]) {
                    sh '''
                        rm -rf .gitops-work
                        AUTH_URL="$(printf '%s' "${GITOPS_REPO_URL}" | sed "s#https://#https://${GIT_USER}:${GIT_TOKEN}@#")"
                        git clone "${AUTH_URL}" .gitops-work
                        ./scripts/update-gitops.sh ".gitops-work" "${DEPLOY_ENV}" "${FULL_IMAGE}"
                        cd .gitops-work
                        if git diff --quiet; then
                          echo "GitOps already references ${FULL_IMAGE}"
                          exit 0
                        fi
                        git config user.name "jenkins"
                        git config user.email "jenkins@local"
                        git add .
                        git commit -m "deploy(sample-api): ${DEPLOY_ENV} ${IMAGE_TAG}"
                        git push origin HEAD
                    '''
                }
            }
        }
    }

    post {
        always {
            sh 'docker logout "${OCIR_REGISTRY}" >/dev/null 2>&1 || true'
            sh 'docker image rm "${FULL_IMAGE}" >/dev/null 2>&1 || true'
            deleteDir()
        }
        success { echo 'CI/CD pipeline completed successfully.' }
        failure { echo 'Pipeline failed. Jenkins performs no direct kubectl deployment.' }
    }
}
