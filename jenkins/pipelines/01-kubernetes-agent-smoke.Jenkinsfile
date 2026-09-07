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
  containers:
    - name: tools
      image: ubuntu:24.04
      command: ["sh", "-c"]
      args: ["sleep 99d"]
      tty: true
'''
            defaultContainer 'tools'
        }
    }

    stages {
        stage('Kubernetes Agent Smoke Test') {
            steps {
                sh '''
                    set -eux
                    echo "Running inside a dynamically created Kubernetes agent pod"
                    hostname
                    id
                    cat /etc/os-release
                    test ! -f /var/run/secrets/kubernetes.io/serviceaccount/token
                    echo "Agent Pod has no Kubernetes ServiceAccount token mounted."
                '''
            }
        }
    }
}
