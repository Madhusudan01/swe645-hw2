// Author: Madhusudan Kharote - SWE645 Homework 2
// Purpose: Jenkins CI/CD pipeline triggered by a GitHub push; it builds the Docker
// image, pushes it to Docker Hub, and rolls it out to the EKS Kubernetes cluster.

pipeline {
    agent any

    environment {
        DOCKERHUB_USER = 'mkharote'                // Docker Hub account
        IMAGE          = "${DOCKERHUB_USER}/swe645-survey"
        TAG            = "${BUILD_NUMBER}"                // unique tag per build
    }

    triggers {
        githubPush()   // fires when the GitHub webhook reports a push
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build Docker Image') {
            steps {
                sh 'docker build -t $IMAGE:$TAG -t $IMAGE:latest .'
            }
        }

        stage('Push to Docker Hub') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'dockerhub-creds',
                                                  usernameVariable: 'DH_USER',
                                                  passwordVariable: 'DH_TOKEN')]) {
                    sh 'echo "$DH_TOKEN" | docker login -u "$DH_USER" --password-stdin'
                    sh 'docker push $IMAGE:$TAG'
                    sh 'docker push $IMAGE:latest'
                }
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                // Jenkins authenticates with its own Kubernetes ServiceAccount token
                // (k8s/jenkins-access.yaml), stored in Jenkins as a Secret file credential,
                // so the pipeline does not depend on temporary AWS Learner Lab keys.
                withCredentials([file(credentialsId: 'eks-kubeconfig', variable: 'KUBECONFIG')]) {
                    sh '''
                        # Swap the image line for this build's tag, then apply
                        sed "s|image: .*swe645-survey:.*|image: $IMAGE:$TAG|" k8s/deployment.yaml | kubectl apply -f -
                        kubectl apply -f k8s/service.yaml
                        kubectl rollout status deployment/survey-app --timeout=180s
                        kubectl get pods -l app=survey-app -o wide
                        kubectl get svc survey-service
                    '''
                }
            }
        }
    }

    post {
        always {
            sh 'docker logout || true'
            sh 'docker image prune -f || true'   // keep the Jenkins disk from filling up
        }
        success { echo "Deployed $IMAGE:$TAG to the EKS cluster" }
        failure { echo 'Pipeline failed - check the stage logs above.' }
    }
}
