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

    - name: git
      image: alpine/git:latest
      command:
        - sleep
      args:
        - 99d

    - name: buildkit
      image: moby/buildkit:rootless
      command:
        - sleep
      args:
        - 99d
      securityContext:
        runAsUser: 1000
        runAsGroup: 1000
'''
        }
    }

    environment {
        REGISTRY  = 'jed.ocir.io'
        NAMESPACE = 'YOUR_OCIR_NAMESPACE'
        IMAGE     = 'sample-api'
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Generate Image Tag') {
            steps {
                container('git') {
                    script {

                        def shortSha = sh(
                            script: 'git rev-parse --short=8 HEAD',
                            returnStdout: true
                        ).trim()

                        def branch = env.BRANCH_NAME
                            .toLowerCase()
                            .replaceAll('[^a-z0-9._-]', '-')

                        env.IMAGE_TAG =
                            "${branch}-${env.BUILD_NUMBER}-${shortSha}"

                        env.FULL_IMAGE =
                            "${env.REGISTRY}/${env.NAMESPACE}/${env.IMAGE}:${env.IMAGE_TAG}"

                        echo "Image tag: ${env.IMAGE_TAG}"
                        echo "Full image: ${env.FULL_IMAGE}"
                    }
                }
            }
        }

        stage('Build Image') {
            steps {
                container('buildkit') {

                    sh '''
                        buildctl-daemonless.sh build \
                          --frontend dockerfile.v0 \
                          --local context=. \
                          --local dockerfile=. \
                          --output type=image,name=${FULL_IMAGE}
                    '''
                }
            }
        }

        stage('Show Result') {
            steps {
                echo "Built image:"
                echo "${FULL_IMAGE}"
            }
        }
    }
}