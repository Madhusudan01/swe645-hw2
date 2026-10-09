// Author: Madhusudan Kharote - SWE645 Homework 2
// Purpose: Jenkins CI/CD pipeline triggered by a GitHub push; it builds the Docker
// image, pushes it to Docker Hub, and rolls it out to the EKS Kubernetes cluster.

pipeline {
    agent any

    environment {
        DOCKERHUB_USER = 'mkharote'                // Docker Hub account
        IMAGE          = "${DOCKERHUB_USER}/swe645-survey"
        TAG            = "${BUILD_NUMBER}"                // unique tag per build
        AWS_REGION     = 'us-east-1'                      // AWS Academy Learner Lab region
        CLUSTER_NAME   = 'swe645-cluster'
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
                // Learner Lab keys are temporary: the whole [default] block (key, secret,
                // session token) is stored as a Secret file and refreshed each lab session.
                withCredentials([file(credentialsId: 'aws-lab-creds', variable: 'AWS_SHARED_CREDENTIALS_FILE')]) {
                    sh '''
                        export KUBECONFIG=$WORKSPACE/kubeconfig
                        aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME
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
        success { echo "Deployed $IMAGE:$TAG to $CLUSTER_NAME" }
        failure { echo 'Pipeline failed - check the stage logs above.' }
    }
}
