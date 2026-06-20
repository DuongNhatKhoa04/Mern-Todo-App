# MERN Todo Capstone

React frontend, Express backend, MongoDB — packaged with Docker and deployed to a
single EC2 with **Jenkins / GitHub Actions CI/CD**, **Prometheus + Grafana**
monitoring, **Terraform** (infra) and **Ansible** (host config).

This README is an **end-to-end runbook**. Follow the sections in order:

1. [Architecture](#1-architecture)
2. [Local quickstart](#2-local-quickstart) (optional, for development)
3. [Provision infrastructure](#3-provision-infrastructure-terraform--ansible)
4. [Get the source & checkout `release/production`](#4-get-the-source--checkout-releaseproduction)
5. [Secrets & deploy user](#5-secrets--deploy-user)
6. [First bring-up (run the app)](#6-first-bring-up-run-the-app)
7. [Nginx + TLS](#7-nginx--tls)
8. [Configure Jenkins](#8-configure-jenkins)
9. [Configure Prometheus](#9-configure-prometheus)
10. [Configure Grafana](#10-configure-grafana)
11. [CI/CD](#11-cicd)
12. [Monitoring reference & troubleshooting](#12-monitoring-reference--troubleshooting)

---

## 1. Architecture

Production runs **three Docker Compose stacks split by lifecycle**, joined by an
external network `mern-network`. Images are **built directly on EC2** — no registry.

| Stack | File | Services | Lifecycle |
|---|---|---|---|
| App | `docker-compose.yml` | frontend, backend, mongo, mongodb-exporter | recreated each deploy |
| Monitoring | `docker-compose.monitoring.yml` | prometheus, grafana, node-exporter, blackbox-exporter | set-and-forget |
| Jenkins | `docker-compose.jenkins.yml` | jenkins (own network `jenkins-net`) | set-and-forget |

- App + Monitoring share `mern-network` so Prometheus can scrape app containers by
  name (`backend:8000`, `mongodb-exporter:9216`, …).
- A deploy touches **only the App stack**. Monitoring and Jenkins are never restarted
  by a release.

| Layer | Tech | Version |
|---|---|---|
| Frontend | React + react-scripts, MUI, Tailwind | 18.2 |
| Backend | Node/Express, Mongoose, JWT, Nodemailer | node:20-alpine / Express 4.18 |
| Database | MongoDB | 7.0 |
| Monitoring | Prometheus / Grafana / node, mongodb, blackbox exporters | 3.4.1 / 12.0.1 |
| CI/CD | Jenkins + GitHub Actions | — |
| Infra | Terraform (AWS) + Ansible | TF >= 0.13, AWS ~> 5.0 |

---

## 2. Local quickstart

The local stack bundles **App + Monitoring** in one file (no Jenkins locally):

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

Stop: `docker compose -f docker-compose.local.yml down` (`-v` to wipe data).

---

## 3. Provision infrastructure (Terraform + Ansible)

Two steps: **Terraform** creates the EC2 + network on AWS and renders the Ansible
inventory; **Ansible** installs Docker, Nginx and Certbot on it.

### 3.1 Terraform — create the EC2

```bash
cd infra/terraform
terraform init
terraform plan
terraform apply      # prints server_ip, ssh_command, *_url, next_step
```

This provisions (everything prefixed `mta-`): a VPC `10.10.1.0/24` + public subnet,
internet gateway + routes, a security group opening **22, 80, 443, 8080, 3001,
9090**, and an Ubuntu 24.04 instance (`c7i-flex.large`, 30 GB gp3). It also renders
`infra/ansible/inventory.ini`. Defaults (region `ap-southeast-1`, SSH key paths) live
in `infra/terraform/variables.tf`. Tear down with `terraform destroy`.

> The SG opens 8080/3001/9090 for initial access. **After [Nginx + TLS](#7-nginx--tls)
> is up, close them** so only 22/80/443 remain (see that section).

### 3.2 Ansible — install Docker / Nginx / Certbot

```bash
cd infra/ansible
ansible-playbook -i inventory.ini playbooks/site.yml
```

Plays run in order: wait-for-SSH → base → docker → nginx (+ Certbot). After this the
host has Docker + Nginx + Certbot. Ansible does **not** configure the app's Nginx
vhost — that's done manually in [section 7](#7-nginx--tls). Details:
[.claude/docs/infrastructure.md](.claude/docs/infrastructure.md).

---

## 4. Get the source & checkout `release/production`

The deployed code lives at `/home/Mern-Todo-App` (git repo). SSH into the box and
clone, then check out the release branch:

```bash
sudo mkdir -p /home/Mern-Todo-App
sudo chown "$USER:$USER" /home/Mern-Todo-App
git clone https://github.com/DuongNhatKhoa04/Mern-Todo-App.git /home/Mern-Todo-App
cd /home/Mern-Todo-App
git checkout release/production
```

Directory layout (source and secrets are **separate** directories):

```text
/home/Mern-Todo-App/                  # source (DEPLOY_PATH), cloned from GitHub
|-- docker-compose.yml                # App
|-- docker-compose.monitoring.yml     # Monitoring
|-- docker-compose.jenkins.yml        # Jenkins
|-- frontend/  backend/  monitoring/  jenkins/
`-- deploy/                           # deploy.sh

/home/secrets/
`-- .env                              # ENV_FILE, created from .env.ec2.example
```

---

## 5. Secrets & deploy user

### 5.1 `.env`

```bash
sudo mkdir -p /home/secrets
sudo cp /home/Mern-Todo-App/.env.ec2.example /home/secrets/.env
sudo chmod 600 /home/secrets/.env
# edit /home/secrets/.env — set real values (see .claude/docs/secrets.md)
```

Key variables:

| Variable | Notes |
|---|---|
| `RELEASE_TAG` | Required, always `production`. CI/CD sets it automatically. |
| `PORT` | Must be `8000` (backend default is 8001 — mismatch breaks healthcheck). |
| `MONGO_ROOT_USER` / `MONGO_ROOT_PASSWORD` | Real values, not `CHANGE_ME`. |
| `MONGO_URI` | Full URI, e.g. `mongodb://admin:<pass>@mongo:27017/todo?authSource=admin`. **URL-encode special chars** in the password (`:`→`%3A`, `@`→`%40`). |
| `JWT_SECRET` | Real secret. |
| `APP_BASE_URL` | Real domain, e.g. `https://nhatkhoa.name.vn` (email links). |
| `GMAIL_*`, `MAIL_FROM` | Gmail App Password. |
| `GRAFANA_ADMIN_USER` / `GRAFANA_ADMIN_PASSWORD` | Grafana login. **Password has no default** — Grafana won't start without it. |

> **Mongo password gotcha:** `mongodb-exporter` reuses `MONGO_URI`. If the password
> contains `:` `@` `/` and is **not** URL-encoded, the exporter fails with
> `invalid dsn: unescaped colon in password`. Keep `MONGO_URI` properly encoded.

### 5.2 Deploy / SSH user

Both CD flows SSH into EC2 as one user and run Docker. This guide uses the Ubuntu
AMI's default **`ubuntu`** user. (The repo's defaults reference `github`; if you use
a dedicated user, substitute it everywhere: Jenkins `EC2_USER`, GitHub Actions var
`EC2_USER`, directory ownership, `authorized_keys`.)

That user **must**:

```bash
# own the source + read the secrets (avoids ".git/FETCH_HEAD: Permission denied")
sudo chown -R ubuntu:ubuntu /home/Mern-Todo-App
sudo chown ubuntu:ubuntu /home/secrets/.env

# run docker without sudo (reconnect SSH afterwards for the group to take effect)
sudo usermod -aG docker ubuntu

# avoid git "dubious ownership"
sudo -u ubuntu git config --global --add safe.directory /home/Mern-Todo-App
```

It also needs its SSH public key in `~/.ssh/authorized_keys` (matching the Jenkins
credential and the GitHub Actions private-key secret) and network access to GitHub.

---

## 6. First bring-up (run the app)

Order matters — create the shared network first, then start the set-and-forget
stacks, then the app:

```bash
cd /home/Mern-Todo-App

# 1. shared network (once)
docker network create mern-network

# 2. set-and-forget stacks
docker compose -f docker-compose.monitoring.yml --env-file /home/secrets/.env up -d
docker compose -f docker-compose.jenkins.yml up -d

# 3. App stack (first time, manual; later done by CI/CD)
RELEASE_TAG=production docker compose -f docker-compose.yml \
  --env-file /home/secrets/.env up -d --build
```

Verify:

```bash
docker compose -f docker-compose.yml --env-file /home/secrets/.env ps
curl -s localhost:8000/health        # 200 when Mongo is connected (503 if not)
```

---

## 7. Nginx + TLS

Host Nginx (installed by Ansible) is the single TLS edge in front of the containers.
Two example configs ship in `deploy/nginx/`:

- `mern-todo.conf.example` — minimal single-domain, App only. Good for HTTP-only.
- `nhatkhoa.name.vn.conf.example` — full production: 4 subdomains on one SAN cert
  over HTTPS — App, `jenkins.`, `grafana.`, `prometheus.`.

### 7.1 Expose only 80/443/22

Every container must bind `127.0.0.1`, and the public ports must be closed in the SG:

- App already binds `127.0.0.1:3000 / 8000`.
- Bind Jenkins/Grafana/Prometheus to `127.0.0.1:8080 / 3001 / 9090`.
- In the SG keep only **22, 80, 443** — close 8080/3001/9090, otherwise
  `http://IP:8080` bypasses TLS and Nginx entirely.

### 7.2 Install the config

```bash
sudo cp deploy/nginx/nhatkhoa.name.vn.conf.example \
        /etc/nginx/sites-available/nhatkhoa.name.vn
sudo ln -s /etc/nginx/sites-available/nhatkhoa.name.vn /etc/nginx/sites-enabled/
```

### 7.3 Certbot bootstrap order (important)

The HTTPS config has `listen 443 ssl` blocks whose `ssl_certificate` lines are
commented out, because the cert doesn't exist yet. nginx refuses any `listen ... ssl`
block with no cert, so `nginx -t` fails — and `certbot --nginx` (which runs `nginx -t`
first) aborts. Break the deadlock by serving the ACME challenge over HTTP first:

1. Enable an HTTP-only config first (`mern-todo.conf.example`, or a temporary server
   block serving `/.well-known/acme-challenge/`), then
   `sudo nginx -t && sudo systemctl reload nginx`.
2. Obtain one SAN cert for all four names:

   ```bash
   sudo certbot certonly --webroot -w /var/www/html \
     -d nhatkhoa.name.vn -d jenkins.nhatkhoa.name.vn \
     -d grafana.nhatkhoa.name.vn -d prometheus.nhatkhoa.name.vn
   ```

3. Enable the full `nhatkhoa.name.vn` config and **uncomment the 8 `ssl_certificate`
   / `ssl_certificate_key` lines** (2 per 443 block).
4. `sudo nginx -t && sudo systemctl reload nginx`.

### 7.4 Per-subdomain auth

App, Jenkins and Grafana each have their own login. **Prometheus has none** — the
config adds Nginx Basic Auth:

```bash
sudo apt-get install -y apache2-utils
sudo htpasswd -c /etc/nginx/.htpasswd-prometheus admin
```

To drop it, remove the two `auth_basic*` lines in the Prometheus server block (or
stop exposing the `prometheus.` subdomain and reach it only through Grafana).

---

## 8. Configure Jenkins

Jenkins runs in its own stack and deploys by **SSH** into EC2. It already ships with
`openssh-client` + the needed plugins (`jenkins/Dockerfile`).

1. **Unlock & create admin** (first boot wizard):

   ```bash
   docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
   ```

   Open `https://jenkins.nhatkhoa.name.vn`, paste it, install suggested plugins,
   create your admin user.

2. **Jenkins URL:** Manage Jenkins → System → Jenkins URL =
   `https://jenkins.nhatkhoa.name.vn/`.

3. **SSH credential** — Manage Jenkins → Credentials → Add:

   ```text
   Kind: SSH Username with private key
   ID: ec2-ssh-key          # must match SSH_CREDENTIAL_ID in Jenkinsfile
   Username: ubuntu         # your deploy user
   Private key: the key matching EC2 authorized_keys
   ```

4. **Pipeline from SCM** — New Item → Pipeline:

   ```text
   Definition: Pipeline script from SCM
   Repository: https://github.com/DuongNhatKhoa04/Mern-Todo-App.git
   Branch Specifier: */release/production
   Script Path: Jenkinsfile
   ```

5. **First manual run** registers the webhook trigger and sets parameters:

   ```text
   EC2_HOST=<EC2 public IP or DNS>
   EC2_USER=ubuntu
   DEPLOY_PATH=/home/Mern-Todo-App
   ENV_FILE=/home/secrets/.env
   ```

6. **GitHub webhook** — repo → Settings → Webhooks → Add:

   ```text
   Payload URL: https://jenkins.nhatkhoa.name.vn/generic-webhook-trigger/invoke?token=mta-production
   Content type: application/json
   Event: Just the push event
   ```

   The filter accepts only `refs/heads/release/production [tag]production`.

> **Choose one CD flow.** Both Jenkins and GitHub Actions deploy on a push to
> `release/production`. To avoid a double deploy, run **only one** — either keep this
> webhook, or disable the GitHub Actions CD workflow (see [section 11](#11-cicd)).

---

## 9. Configure Prometheus

Prometheus config is `monitoring/prometheus/prometheus.yml` — no UI setup needed. It
scrapes four jobs: `prometheus`, `node` (`node-exporter:9100`), `mongodb`
(`mongodb-exporter:9216`), and `application-health` (blackbox HTTP probe of
`backend:8000/health` and `frontend:3000/health`).

Verify after bring-up: open **Prometheus → Status → Targets** (or
`https://prometheus.nhatkhoa.name.vn/targets`). All jobs should be **UP**. A `mongodb`
target that is DOWN almost always means the App stack isn't running or the exporter
can't auth — see [section 12](#12-monitoring-reference--troubleshooting).

Reload config without restart (lifecycle API is enabled):

```bash
curl -X POST http://localhost:9090/-/reload
```

---

## 10. Configure Grafana

1. **Login:** `https://grafana.nhatkhoa.name.vn` — user/pass = `GRAFANA_ADMIN_USER` /
   `GRAFANA_ADMIN_PASSWORD`.
2. **Datasource is auto-provisioned** (Prometheus, set as default) — no manual setup.
   Check under Connections → Data sources → Prometheus → Test.
3. **Import dashboards** (the repo doesn't provision dashboards) — Dashboards → New →
   Import → enter ID → select the Prometheus datasource:

   | Dashboard | ID |
   |---|---|
   | Node Exporter Full | `1860` |
   | MongoDB (Percona) | `2583` |
   | Prometheus Blackbox | `7587` |

4. **Behind Nginx**, set the root URL so links/redirects work (env in
   `docker-compose.monitoring.yml` or `.env`):

   ```yaml
   GF_SERVER_ROOT_URL=https://grafana.nhatkhoa.name.vn
   ```

> If a MongoDB dashboard shows empty **Replica Set** panels (Member Health/State,
> Oplog), that's expected — this Mongo runs **standalone**, not as a replica set.

---

## 11. CI/CD

Two automated flows, kept separate so they don't deploy at once. Both ultimately SSH
into EC2 and run the shared **`deploy/deploy.sh`** (checkout the exact release commit,
build frontend/backend on EC2, recreate them, wait for both health checks — App stack
only).

### Release convention

A deploy happens only when both hold:

1. branch = `release/production`
2. commit message is **exactly** `[tag]production` (prefixes, suffixes, spaces or
   extra lines are rejected).

### GitHub Actions (CI gate → CD)

- **`ci.yml`** runs on every push/PR but a `gate` job only lets the build proceed
  when the commit message is `[tag]production` (or it's a PR). A plain test commit
  skips the whole build.
- **`cd.yml`** is triggered by `workflow_run` — it runs **after CI completes
  successfully** on `release/production`, and only when the commit message is
  `[tag]production`. So **build must pass before deploy**.

Required repo config — Settings → Secrets and variables → Actions:

| Type | Name | Value |
|---|---|---|
| Secret | `EC2_HOST` | EC2 public IP/DNS |
| Secret | `EC2_SSH_PRIVATE_KEY` | private key matching the deploy user's `authorized_keys` |
| Variable | `EC2_USER` | `ubuntu` |
| Variable | `DEPLOY_PATH` | `/home/Mern-Todo-App` |
| Variable | `ENV_FILE` | `/home/secrets/.env` |

> **`cd.yml` must live on the default branch (`main`)** for `workflow_run` to fire —
> GitHub reads the trigger definition from the default branch. Merge it to `main`.

### Jenkins

Triggered by the GitHub webhook on a push to `release/production` whose commit is
`[tag]production`. See [section 8](#8-configure-jenkins).

### Trigger a release

```bash
git switch release/production
git add -A && git commit -m "feat: ..."        # normal work — only CI runs, no deploy
git push origin release/production

# when ready to deploy production:
git commit --allow-empty -m "[tag]production"  # type -m directly (avoid CRLF in the message)
git push origin release/production
```

> **Pick one flow per release.** If GitHub Actions is your CD, disable the Jenkins
> webhook; if Jenkins is, disable the GitHub Actions CD workflow (Actions → CD →
> Disable workflow). Running both deploys the same commit twice.

---

## 12. Monitoring reference & troubleshooting

**What's scraped:** node-exporter (host CPU/RAM/disk), mongodb-exporter (Mongo
stats), blackbox-exporter (HTTP `/health` probes of backend & frontend), Prometheus
itself.

Common issues:

| Symptom | Cause / fix |
|---|---|
| Grafana panels all "No data / N/A" | `mongodb` target DOWN, or dashboard filters by a label the metrics lack. Check `mongodb_up` in Prometheus. |
| `mongodb-exporter` log: `unescaped colon in password` | `MONGO_URI` password not URL-encoded (`:`→`%3A`). Exporter uses `MONGODB_URI: ${MONGO_URI}`. |
| `mongodb` target DOWN | App stack not running, or exporter not on `mern-network`. `docker network inspect mern-network`. |
| Grafana restart loop | `GRAFANA_ADMIN_PASSWORD` missing in `.env`. |
| Replica Set panels empty | Expected — Mongo is standalone. |
| `mern-network not found` | Run `docker network create mern-network` before `up`. |

> `deploy/deploy.sh` only recreates **frontend + backend**. If you change `mongo` or
> `mongodb-exporter`, recreate them manually:
> `docker compose -f docker-compose.yml --env-file /home/secrets/.env up -d --force-recreate mongodb-exporter`.

Verify the exporter:

```bash
docker logs mongodb-exporter --tail 20          # no "level=error" lines
curl -s localhost:9216/metrics | grep '^mongodb_up'   # mongodb_up 1
```

---
