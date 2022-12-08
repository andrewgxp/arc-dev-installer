#!/bin/bash

set -e

# Default options
GHE_TOKEN=""
REPO_NAME=""
REPO_OWNER=""
DIRECTORY=$(pwd)

usage() {
    grep '^#/' < "$0" | cut -c 4-
    exit 2
}

prompt() {
    read -p "$1 Please type 'Yes' or 'No': " -r

    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        if [[ ! $REPLY =~ ^[Nn][Oo]$ ]]; then
            echo "Assuming you answered No"
        fi
        exit 1
    fi
}

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            ;;
        -token|--token)
            GHE_TOKEN=$2
            shift 2
            ;;
        -repo|--repo-name)
            REPO_NAME=$2
            shift 2
            ;;
        -owner|--repo-owner)
            REPO_OWNER=$2
            shift 2
            ;;
        *)
            >&2 echo "Unrecognized argument: $1"
            usage
            ;;
    esac
done

if [[ -z $GHE_TOKEN ]]; then
 echo "The GHE_TOKEN value is empty and needs to with --token"
 usage
fi

if [[ -z $REPO_NAME ]]; then
 echo "The REPO_NAME value is empty and needs to with --repo-name"
 usage
fi

if [[ -z $REPO_OWNER ]]; then
 echo "The REPO_OWNER value is empty and needs to with --repo-owner"
 usage
fi

install-docker() {
    sudo apt update
    sudo apt install apt-transport-https ca-certificates curl software-properties-common -y
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    if [ ! -f /etc/apt/sources.list.d/docker.list ]
then
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
else
    echo "The docker.list file already exists, moving on!"
fi
    sudo apt update
    sudo apt install docker-ce -y 
    sudo systemctl start docker
    sudo systemctl enable docker
    sudo usermod -aG docker ${USER}
}

install-minikube() {
    curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
    sudo install minikube-linux-amd64 /usr/local/bin/minikube
    sudo su ${USER} -c "minikube start"
}

install-cert-manager() {
    sudo su ${USER} -c "minikube kubectl -- apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.8.2/cert-manager.yaml"
    sleep 180
}

install-actions-runner-controller() {
    set +e
    sudo su ${USER} -c "minikube kubectl -- create -f https://github.com/actions-runner-controller/actions-runner-controller/releases/download/v0.26.0/actions-runner-controller.yaml"
    sleep 180
    sudo su ${USER} -c "minikube kubectl -- create secret generic controller-manager -n actions-runner-system --from-literal=github_token=${GHE_TOKEN}"
    sleep 180
    set -e
}

create-runner-controller-init() {
cat << EOF > runner-init.yml
apiVersion: actions.summerwind.dev/v1alpha1
kind: RunnerDeployment
metadata:
  name: example-runner-deployment
spec:
  template:
    spec:
      repository: $REPO_OWNER/$REPO_NAME
---
apiVersion: actions.summerwind.dev/v1alpha1
kind: HorizontalRunnerAutoscaler
metadata:
  name: example-runner-deployment-autoscaler
spec:
  scaleTargetRef:
    kind: RunnerDeployment
    # # In case the scale target is RunnerSet:
    # kind: RunnerSet
    name: example-runner-deployment
  minReplicas: 1
  maxReplicas: 5
  metrics:
  - type: TotalNumberOfQueuedAndInProgressWorkflowRuns
    repositoryNames:
    - $REPO_NAME
EOF
}

apply-runner-controller-init() {

    sudo su ${USER} -c "minikube kubectl -- apply -f runner-init.yml"
}

install-docker;
install-minikube;
install-cert-manager;
install-actions-runner-controller;
create-runner-controller-init;
apply-runner-controller-init;
