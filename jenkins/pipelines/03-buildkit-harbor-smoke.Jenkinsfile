pipeline {
    agent {
        kubernetes {
            cloud 'kubernetes'
            yamlFile 'jenkins/pod-templates/ci-buildkit-harbor.yaml'
            defaultContainer 'git'
            retries 2
        }
    }

    parameters {
        string(name: 'HARBOR_PROJECT', defaultValue: 'dev', description: 'Existing Harbor project.')
    }

    environment {
        HARBOR_REGISTRY = 'harbor.192-168-100-240.nip.io'
        HARBOR_CREDENTIAL_ID = 'harbor-robot-credentials'
        IMAGE_NAME = 'sample-api'
    }

    stages {
        stage('Checkout') {
            steps { checkout scm }
        }

        stage('Metadata') {
            steps {
                script {
                    def sha = sh(script: 'git rev-parse --short=8 HEAD', returnStdout: true).trim()
                    def branch = (env.BRANCH_NAME ?: 'manual').toLowerCase().replaceAll('[^a-z0-9._-]', '-')
                    env.IMAGE_TAG = "${branch}-${env.BUILD_NUMBER}-${sha}"
                    env.FULL_IMAGE = "${env.HARBOR_REGISTRY}/${params.HARBOR_PROJECT}/${env.IMAGE_NAME}:${env.IMAGE_TAG}"
                    echo "Image: ${env.FULL_IMAGE}"
                }
            }
        }

        stage('Build and Push to Harbor') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: "${HARBOR_CREDENTIAL_ID}",
                    usernameVariable: 'HARBOR_USER',
                    passwordVariable: 'HARBOR_PASSWORD'
                )]) {
                    container('buildkit') {
                        sh '''
                            set -eu
                            DOCKER_CONFIG_DIR="${WORKSPACE}/.docker"
                            mkdir -p "${DOCKER_CONFIG_DIR}"
                            chmod 700 "${DOCKER_CONFIG_DIR}"

                            AUTH="$(printf '%s:%s' "${HARBOR_USER}" "${HARBOR_PASSWORD}" | base64 | tr -d '\n')"
                            printf '{"auths":{"%s":{"auth":"%s"}}}\n' \
                              "${HARBOR_REGISTRY}" "${AUTH}" > "${DOCKER_CONFIG_DIR}/config.json"
                            chmod 600 "${DOCKER_CONFIG_DIR}/config.json"
                            export DOCKER_CONFIG="${DOCKER_CONFIG_DIR}"

                            buildctl-daemonless.sh build \
                              --frontend dockerfile.v0 \
                              --local context=. \
                              --local dockerfile=. \
                              --output "type=image,name=${FULL_IMAGE},push=true"

                            rm -rf "${DOCKER_CONFIG_DIR}"
                        '''
                    }
                }
            }
        }
    }

    post {
        always {
            sh 'rm -rf "${WORKSPACE}/.docker" || true'
            deleteDir()
        }
    }
}
