pipeline {
    agent {
        kubernetes {
            cloud 'kubernetes'
            yamlFile 'jenkins/pod-templates/ci-buildkit.yaml'
            defaultContainer 'dotnet'
            retries 2
        }
    }

    options {
        timestamps()
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '20'))
        skipDefaultCheckout(true)
    }

    parameters {
        booleanParam(name: 'ENABLE_SONAR', defaultValue: false, description: 'Run SonarQube analysis and Quality Gate.')
        booleanParam(name: 'ENABLE_TRIVY', defaultValue: true, description: 'Scan the OCI image with Trivy.')
        booleanParam(name: 'PUSH_IMAGE', defaultValue: false, description: 'Push immutable image to OCIR. False exports an OCI tar only.')
        string(name: 'OCIR_NAMESPACE', defaultValue: 'CHANGE_ME', description: 'OCI Object Storage / Container Registry namespace.')
        string(name: 'GITOPS_REPO_URL', defaultValue: '', description: 'HTTPS URL of separate GitOps repository. Empty skips CD handoff.')
    }

    environment {
        OCIR_REGISTRY = 'jed.ocir.io'
        IMAGE_NAME = 'sample-api'
        OCIR_CREDENTIAL_ID = 'ocir-credentials'
        GITOPS_CREDENTIAL_ID = 'gitops-credentials'
        SONARQUBE_SERVER = 'SonarQubeServer'
        SONAR_PROJECT_KEY = 'sample-api'
    }

    stages {
        stage('Checkout') {
            steps {
                container('git') {
                    checkout scm
                }
            }
        }

        stage('Metadata') {
            steps {
                container('git') {
                    script {
                        def shortSha = sh(script: 'git rev-parse --short=8 HEAD', returnStdout: true).trim()
                        def branch = env.BRANCH_NAME ?: 'manual'
                        def safeBranch = branch.toLowerCase().replaceAll('[^a-z0-9._-]', '-')
                        def environmentMap = [
                            'development': 'dev',
                            'qa': 'qa',
                            'preprod': 'preprod',
                            'main': 'prod'
                        ]

                        env.DEPLOY_ENV = environmentMap.get(branch, '')
                        env.IMAGE_TAG = "${safeBranch}-${env.BUILD_NUMBER}-${shortSha}"
                        env.IMAGE_REPOSITORY = "${env.OCIR_REGISTRY}/${params.OCIR_NAMESPACE}/${env.IMAGE_NAME}"
                        env.FULL_IMAGE = "${env.IMAGE_REPOSITORY}:${env.IMAGE_TAG}"

                        echo "Branch:      ${branch}"
                        echo "Environment: ${env.DEPLOY_ENV ?: 'CI only'}"
                        echo "Image:       ${env.FULL_IMAGE}"
                    }
                }
            }
        }

        stage('Validate Configuration') {
            steps {
                script {
                    if (params.OCIR_NAMESPACE == 'CHANGE_ME' || !params.OCIR_NAMESPACE.trim()) {
                        error('Set OCIR_NAMESPACE to your OCI registry namespace.')
                    }
                    if (params.GITOPS_REPO_URL?.trim() && !params.PUSH_IMAGE) {
                        error('GitOps update requires PUSH_IMAGE=true.')
                    }
                }
            }
        }

        stage('Restore') {
            steps {
                sh 'dotnet restore SampleCiCd.slnx'
            }
        }

        stage('SonarQube Begin') {
            when { expression { params.ENABLE_SONAR } }
            steps {
                withSonarQubeEnv("${SONARQUBE_SERVER}") {
                    sh '''
                        dotnet tool restore
                        dotnet sonarscanner begin \
                          /k:"${SONAR_PROJECT_KEY}" \
                          /d:sonar.token="${SONAR_AUTH_TOKEN}"
                    '''
                }
            }
        }

        stage('Build') {
            steps {
                sh 'dotnet build SampleCiCd.slnx -c Release --no-restore'
            }
        }

        stage('Unit Tests') {
            steps {
                sh '''
                    dotnet test tests/SampleApi.Tests/SampleApi.Tests.csproj \
                      -c Release \
                      --no-build \
                      --logger "trx;LogFileName=test-results.trx"
                '''
            }
            post {
                always {
                    archiveArtifacts artifacts: '**/TestResults/*.trx', allowEmptyArchive: true
                }
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

        stage('Build Image') {
            steps {
                script {
                    if (params.PUSH_IMAGE) {
                        withCredentials([usernamePassword(
                            credentialsId: "${OCIR_CREDENTIAL_ID}",
                            usernameVariable: 'OCIR_USER',
                            passwordVariable: 'OCIR_TOKEN'
                        )]) {
                            container('buildkit') {
                                sh '''
                                    set -eu
                                    DOCKER_CONFIG_DIR="${WORKSPACE}/.docker"
                                    mkdir -p "${DOCKER_CONFIG_DIR}"
                                    chmod 700 "${DOCKER_CONFIG_DIR}"
                                    AUTH="$(printf '%s:%s' "${OCIR_USER}" "${OCIR_TOKEN}" | base64 | tr -d '\n')"
                                    printf '{"auths":{"%s":{"auth":"%s"}}}\n' \
                                      "${OCIR_REGISTRY}" "${AUTH}" > "${DOCKER_CONFIG_DIR}/config.json"
                                    chmod 600 "${DOCKER_CONFIG_DIR}/config.json"
                                    export DOCKER_CONFIG="${DOCKER_CONFIG_DIR}"

                                    buildctl-daemonless.sh build \
                                      --frontend dockerfile.v0 \
                                      --local context=. \
                                      --local dockerfile=. \
                                      --opt "build-arg:APP_VERSION=${IMAGE_TAG}" \
                                      --output "type=image,name=${FULL_IMAGE},push=true"

                                    rm -rf "${DOCKER_CONFIG_DIR}"
                                '''
                            }
                        }
                    } else {
                        container('buildkit') {
                            sh '''
                                set -eu
                                rm -f "${WORKSPACE}/image.oci.tar"
                                buildctl-daemonless.sh build \
                                  --frontend dockerfile.v0 \
                                  --local context=. \
                                  --local dockerfile=. \
                                  --opt "build-arg:APP_VERSION=${IMAGE_TAG}" \
                                  --output "type=oci,dest=${WORKSPACE}/image.oci.tar"
                            '''
                        }
                    }
                }
            }
        }

        stage('Trivy Image Scan') {
            when { expression { params.ENABLE_TRIVY } }
            steps {
                script {
                    if (params.PUSH_IMAGE) {
                        withCredentials([usernamePassword(
                            credentialsId: "${OCIR_CREDENTIAL_ID}",
                            usernameVariable: 'TRIVY_USERNAME',
                            passwordVariable: 'TRIVY_PASSWORD'
                        )]) {
                            container('trivy') {
                                sh '''
                                    trivy image \
                                      --exit-code 1 \
                                      --severity HIGH,CRITICAL \
                                      --ignore-unfixed \
                                      "${FULL_IMAGE}"
                                '''
                            }
                        }
                    } else {
                        container('trivy') {
                            sh '''
                                trivy image \
                                  --input "${WORKSPACE}/image.oci.tar" \
                                  --exit-code 1 \
                                  --severity HIGH,CRITICAL \
                                  --ignore-unfixed
                            '''
                        }
                    }
                }
            }
        }

        stage('Production Approval') {
            when {
                allOf {
                    expression { env.DEPLOY_ENV == 'prod' }
                    expression { params.PUSH_IMAGE }
                    expression { params.GITOPS_REPO_URL?.trim() }
                }
            }
            steps {
                input message: "Promote ${env.FULL_IMAGE} to PROD GitOps?", ok: 'Promote'
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
                withCredentials([usernamePassword(
                    credentialsId: "${GITOPS_CREDENTIAL_ID}",
                    usernameVariable: 'GIT_USER',
                    passwordVariable: 'GIT_TOKEN'
                )]) {
                    container('git') {
                        sh '''
                            set -eu
                            rm -rf .gitops-work
                            export GIT_ASKPASS="${WORKSPACE}/scripts/git-askpass.sh"
                            export GIT_TERMINAL_PROMPT=0

                            git clone "${GITOPS_REPO_URL}" .gitops-work
                            ./scripts/update-gitops.sh .gitops-work "${DEPLOY_ENV}" "${FULL_IMAGE}"
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
    }

    post {
        always {
            sh '''
                rm -rf "${WORKSPACE}/.docker" \
                       "${WORKSPACE}/.trivycache" \
                       "${WORKSPACE}/image.oci.tar" || true
            '''
            deleteDir()
        }
        success { echo 'CI/CD pipeline completed successfully.' }
        failure { echo 'Pipeline failed. Jenkins did not deploy directly to Kubernetes.' }
    }
}
