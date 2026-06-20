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

## Production on EC2

One Ubuntu 24.04 EC2 runs the 3 lifecycle stacks joined by an external
`mern-network`. Images are built on the box — no registry. First bring-up:

1. Install Docker, Nginx and Certbot on the host (handled by Ansible — see
   [.claude/docs/infrastructure.md](.claude/docs/infrastructure.md)).
2. Lay out directories and secrets (see **EC2 Directory** below).
3. Create the shared network and start the set-and-forget stacks:

   ```bash
   docker network create mern-network
   docker compose -f docker-compose.monitoring.yml up -d
   docker compose -f docker-compose.jenkins.yml up -d
   ```

4. Configure Jenkins (see **Jenkins Setup**). The App stack is then deployed by
   CI/CD via `deploy/deploy.sh`, or manually:

   ```bash
   cd /home/Mern-Todo-App
   RELEASE_TAG=production docker compose -f docker-compose.yml \
     --env-file /home/secrets/.env up -d --build
   ```

5. Put Nginx + TLS in front of the containers (see **Nginx + TLS**).

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

## Nginx + TLS

Host Nginx (installed via Ansible) is the single TLS edge in front of the
containers. Two example configs ship in `deploy/nginx/`:

- `mern-todo.conf.example` — minimal single-domain, App only (`/` → `3000`,
  `/api/` → `8000`). Fine for a quick HTTP-only bring-up.
- `nhatkhoa.name.vn.conf.example` — full production: 4 subdomains on one SAN
  cert over HTTPS — App, `jenkins.`, `grafana.`, `prometheus.`.

### Expose only 80/443/22

For Nginx to be the only TLS edge, every container must bind `127.0.0.1` and the
public ports must be closed in the Security Group:

- App already binds `127.0.0.1:3000 / 8000`.
- Bind Jenkins/Grafana/Prometheus to `127.0.0.1:8080 / 3001 / 9090`.
- In the SG keep only `80, 443, 22` — close `8080/3001/9090`, otherwise
  `http://IP:8080` bypasses TLS and Nginx entirely.

### Install the config

```bash
sudo cp deploy/nginx/nhatkhoa.name.vn.conf.example \
        /etc/nginx/sites-available/nhatkhoa.name.vn
sudo ln -s /etc/nginx/sites-available/nhatkhoa.name.vn /etc/nginx/sites-enabled/
```

### Certbot bootstrap order (important)

The HTTPS config has `listen 443 ssl` blocks whose `ssl_certificate` lines are
commented out, because the cert does not exist yet. nginx refuses any
`listen ... ssl` block with no cert, so `nginx -t` fails — and `certbot --nginx`
(which runs `nginx -t` first) aborts. Break the deadlock by serving the ACME
challenge over HTTP first, then enabling 443:

1. Enable an HTTP-only config first (`mern-todo.conf.example`, or a temporary
   server block serving `/.well-known/acme-challenge/`), then
   `sudo nginx -t && sudo systemctl reload nginx`.
2. Obtain one SAN cert for all four names:

   ```bash
   sudo certbot certonly --webroot -w /var/www/html \
     -d nhatkhoa.name.vn -d jenkins.nhatkhoa.name.vn \
     -d grafana.nhatkhoa.name.vn -d prometheus.nhatkhoa.name.vn
   ```

3. Enable the full `nhatkhoa.name.vn` config and **uncomment the 8
   `ssl_certificate` / `ssl_certificate_key` lines** (2 per 443 block).
4. `sudo nginx -t && sudo systemctl reload nginx`.

### Per-subdomain auth

App, Jenkins and Grafana each have their own login. **Prometheus has none** — the
config adds Nginx Basic Auth for it:

```bash
sudo apt-get install -y apache2-utils
sudo htpasswd -c /etc/nginx/.htpasswd-prometheus admin
```

To drop Prometheus auth, remove the two `auth_basic*` lines in its server block
(or stop exposing the `prometheus.` subdomain and reach it only through Grafana).
