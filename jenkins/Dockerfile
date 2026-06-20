FROM jenkins/jenkins:lts-jdk21

USER root

# openssh-client: để pipeline SSH vào EC2 chạy deploy/deploy.sh (mô hình SSH thống nhất).
RUN apt-get update \
    && apt-get install -y --no-install-recommends openssh-client \
    && rm -rf /var/lib/apt/lists/*

RUN jenkins-plugin-cli --plugins \
    workflow-aggregator \
    git \
    credentials-binding \
    ssh-agent \
    generic-webhook-trigger

# Admin/security do setup wizard của Jenkins lo (unlock bằng initialAdminPassword
# lần đầu, rồi tự tạo user). Không auto-tạo admin từ env.

USER jenkins
