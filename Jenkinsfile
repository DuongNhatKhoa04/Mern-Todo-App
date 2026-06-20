pipeline {
    agent any

    options {
        skipDefaultCheckout(true)
        disableConcurrentBuilds()
    }

    triggers {
        GenericTrigger(
            genericVariables: [
                [key: 'webhookRef', value: '$.ref'],
                [key: 'webhookMessage', value: '$.head_commit.message']
            ],
            causeString: 'Release webhook: $webhookRef $webhookMessage',
            token: 'mta-production',
            printContributedVariables: false,
            printPostContent: false,
            regexpFilterText: '$webhookRef $webhookMessage',
            regexpFilterExpression: '^refs/heads/release/production \\[tag\\]production$'
        )
    }

    parameters {
        string(
            name: 'EC2_HOST',
            defaultValue: '',
            description: 'EC2 public IP or DNS name'
        )
        string(
            name: 'EC2_USER',
            defaultValue: 'ubuntu',
            description: 'SSH user on EC2'
        )
        string(
            name: 'DEPLOY_PATH',
            defaultValue: '/home/Mern-Todo-App',
            description: 'Git repo (source) dir on EC2'
        )
        string(
            name: 'ENV_FILE',
            defaultValue: '/home/secrets/.env',
            description: 'Path to .env on EC2 (secrets, outside source dir)'
        )
    }

    environment {
        SSH_CREDENTIAL_ID = 'ec2-ssh-key'
        RELEASE_BRANCH = 'release/production'
        RELEASE_TAG = 'production'
    }

    stages {
        stage('Validate') {
            steps {
                script {
                    if (!params.EC2_HOST?.trim()) {
                        error('EC2_HOST is required')
                    }

                    def scmVars = checkout scm
                    def branch = scmVars.GIT_BRANCH ?: env.BRANCH_NAME ?: ''
                    if (!(branch == env.RELEASE_BRANCH || branch.endsWith("/${env.RELEASE_BRANCH}"))) {
                        error("Only branch ${env.RELEASE_BRANCH} is allowed. Current branch: ${branch}")
                    }

                    def commitMessage = sh(
                        script: "git log -1 --pretty=%B | perl -0pe 's/\\n\\z//'",
                        returnStdout: true
                    )
                    if (!(commitMessage =~ /^\[tag\]production$/).matches()) {
                        error('Commit message must be exactly [tag]production')
                    }

                    env.RELEASE_COMMIT = sh(
                        script: 'git rev-parse HEAD',
                        returnStdout: true
                    ).trim()
                }
            }
        }

        stage('Deploy') {
            steps {
                sshagent(credentials: [env.SSH_CREDENTIAL_ID]) {
                    sh '''
                        set -eu

                        ssh -o StrictHostKeyChecking=accept-new \
                          "${EC2_USER}@${EC2_HOST}" \
                          "DEPLOY_PATH='${DEPLOY_PATH}' \
                           ENV_FILE='${ENV_FILE}' \
                           RELEASE_TAG='${RELEASE_TAG}' \
                           RELEASE_COMMIT='${RELEASE_COMMIT}' \
                           bash -s" < deploy/deploy.sh
                    '''
                }
            }
        }
    }
}
