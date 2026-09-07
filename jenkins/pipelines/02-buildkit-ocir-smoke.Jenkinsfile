pipeline {
    agent {
        kubernetes {
            cloud 'kubernetes'
            retries 2
            yaml '''
apiVersion: v1
kind: Pod
spec:
  automountServiceAccountToken: false
  securityContext:
    fsGroup: 1000
  containers:
    - name: buildkit
      image: moby/buildkit:v0.30.0-rootless
      command: ["sh", "-c"]
      args: ["sleep 99d"]
      tty: true
      env:
        - name: BUILDKITD_FLAGS
          value: --oci-worker-no-process-sandbox
      securityContext:
        runAsUser: 1000
        runAsGroup: 1000
        allowPrivilegeEscalation: false
        seccompProfile: { type: Unconfined }
        appArmorProfile: { type: Unconfined }
      volumeMounts:
        - name: buildkit-state
          mountPath: /home/user/.local/share/buildkit
  volumes:
    - name: buildkit-state
      emptyDir: {}
'''
            defaultContainer 'buildkit'
        }
    }

    parameters {
        string(name: 'OCIR_NAMESPACE', defaultValue: 'CHANGE_ME', description: 'OCI Object Storage / Registry namespace')
    }

    environment {
        OCIR_REGISTRY = 'jed.ocir.io'
        OCIR_CREDENTIAL_ID = 'ocir-credentials'
    }

    stages {
        stage('Create Smoke Dockerfile') {
            steps {
                sh '''
                    cat > Dockerfile <<'EOF'
FROM busybox:1.36
CMD ["sh", "-c", "echo BuildKit OCIR smoke image && sleep 3600"]
EOF
                '''
            }
        }

        stage('Build and Push') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: "${OCIR_CREDENTIAL_ID}",
                    usernameVariable: 'OCIR_USER',
                    passwordVariable: 'OCIR_TOKEN'
                )]) {
                    sh '''
                        set -eu
                        test "${OCIR_NAMESPACE}" != "CHANGE_ME"

                        IMAGE="${OCIR_REGISTRY}/${OCIR_NAMESPACE}/buildkit-smoke:${BUILD_NUMBER}"
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
                          --output "type=image,name=${IMAGE},push=true"

                        rm -rf "${DOCKER_CONFIG_DIR}"
                        echo "Pushed ${IMAGE}"
                    '''
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
