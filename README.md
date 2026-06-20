# MERN Todo Capstone

React frontend, Express backend, MongoDB, Jenkins CI/CD, Prometheus and
Grafana.

## Docker Configurations

- `docker-compose.local.yml`: Docker Desktop dev stack (App + Monitoring in one
  file, `-local` resource names). No Jenkins locally.
- Production is split into 3 files by lifecycle, joined by an external
  `mern-network`:
  - `docker-compose.yml` — App (frontend, backend, mongo, mongodb-exporter).
  - `docker-compose.monitoring.yml` — Prometheus, Grafana, exporters.
  - `docker-compose.jenkins.yml` — Jenkins (own network).
  Images are built directly on EC2. No container registry is used.

## Local Stack

```powershell
Copy-Item .env.local.example .env.local
docker compose --env-file .env.local -f docker-compose.local.yml up -d --build
```

| Service | URL |
|---|---|
| Application | http://localhost:3000 |
| Backend health | http://localhost:8000/health |
| Grafana | http://localhost:3001 |
| Prometheus | http://localhost:9090 |

## Jenkins CI/CD

Both CD flows (Jenkins and GitHub Actions) SSH into EC2 and run the shared
`deploy/deploy.sh`: checkout the exact release commit, build frontend/backend
images on EC2, recreate them, and wait for both health checks. Only the App stack
(`docker-compose.yml`) is touched.

Jenkins accepts only branch `release/production`. The complete commit message
must match:

```text
[tag]production
```

This creates local images on EC2:

```text
mta-frontend:production
mta-backend:production
```

Messages containing prefixes, suffixes, spaces, or extra lines are rejected.

## EC2 Directory

Source (git repo) and the secrets `.env` live in **separate** directories:

```text
/home/Mern-Todo-App/                  # source (DEPLOY_PATH), cloned from GitHub
|-- docker-compose.yml                # App
|-- docker-compose.monitoring.yml     # Monitoring
|-- docker-compose.jenkins.yml        # Jenkins
|-- frontend/
|-- backend/
|-- monitoring/
|-- jenkins/
`-- deploy/                           # deploy.sh

/home/secrets/
`-- .env                              # ENV_FILE, created from .env.ec2.example
```

Create `.env` from `.env.ec2.example` and protect it:

```bash
chmod 600 /home/secrets/.env
```

The EC2 user `github` (used by both CD flows via SSH) must:

- Have SSH public-key access (matches Jenkins credential `ec2-ssh-key` and the
  GitHub Actions secret `EC2_SSH_PRIVATE_KEY`)..env.local.example
- Have access to `/home/Mern-Todo-App` and `/home/secrets/.env`.
- Be allowed to run Docker without `sudo`.
- Be able to fetch from GitHub.

## Jenkins Setup

Jenkins runs in its own stack (`docker-compose.jenkins.yml`) and deploys by **SSH**
into EC2. First boot uses the standard setup wizard — unlock with
`docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword`, then create
your admin user.

Create an SSH credential:

```text
Kind: SSH Username with private key
ID: ec2-ssh-key
Username: github
Private key: the key matching EC2 authorized_keys
```

Create a Pipeline from SCM:

```text
Repository: https://github.com/DuongNhatKhoa04/Mern-Todo-App.git
Branch Specifier: */release/production
Script Path: Jenkinsfile
```

The first manual run registers the Generic Webhook Trigger configuration.
Set the build parameters:

```text
EC2_HOST=<EC2 public IP or DNS>
EC2_USER=github
DEPLOY_PATH=/home/Mern-Todo-App
ENV_FILE=/home/secrets/.env
```

GitHub webhook:

```text
Payload URL:
https://<jenkins-domain>/generic-webhook-trigger/invoke?token=mta-production

Content type: application/json
Event: Push
```

The webhook filter accepts only:

```text
refs/heads/release/production [tag]production
```

## Trigger A Release

```bash
git switch release/production
git commit -m "[tag]production"
git push origin release/production
```

## Nginx

Host Nginx proxies:

- `/` to `127.0.0.1:3000`
- `/api/` to `127.0.0.1:8000/api/`

Use `deploy/nginx/mern-todo.conf.example`, then configure Certbot on the host.
