# Infra — Terraform + Ansible

Hai bước: **Terraform** tạo EC2 trên AWS và sinh inventory; **Ansible** cài
base + Docker + Nginx/Certbot lên máy đó. Việc đưa code/`.env` lên EC2 và triển khai
container là do **Jenkins / GitHub Actions** đảm nhận (xem
[../.claude/docs/cicd-pipeline.md](../.claude/docs/cicd-pipeline.md)), **không** phải Ansible.

> Tài liệu nền: [../.claude/docs/infrastructure.md](../.claude/docs/infrastructure.md).

## Yêu cầu trên máy local

```bash
# Terraform >= 1.6 — https://developer.hashicorp.com/terraform/install
# Ansible >= 2.14
pip install ansible
ansible-galaxy collection install community.general ansible.posix

# AWS CLI đã configure (region khớp aws_region, mặc định ap-southeast-1)
aws configure
```

## Bước 1 — Tạo SSH key (nếu chưa có)

```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
```

## Bước 2 — Terraform tạo VPS

```bash
cd infra/terraform

cp terraform.tfvars.example terraform.tfvars
# Sửa ssh_public_key_path / ssh_private_key_path thành ĐƯỜNG DẪN TUYỆT ĐỐI.

terraform init
terraform plan
terraform apply              # ~2-3 phút
terraform output             # server_ip, ssh_command, jenkins_url, grafana_url...
```

Terraform tự sinh `infra/ansible/inventory.ini` với IP của server (xem
`templates/inventory.tpl`). Biến cấu hình: `variables.tf`.

## Bước 3 — Ansible cài đặt nền

```bash
cd infra/ansible
ansible-playbook -i inventory.ini playbooks/site.yml
```

`playbooks/site.yml` chạy tuần tự:

1. Chờ SSH sẵn sàng (`wait_for_connection`).
2. **base** — cập nhật hệ thống, gói cơ bản, timezone, swap 1GB, tạo `/opt/capstone`.
3. **docker** — cài Docker Engine + compose plugin, thêm `ubuntu` vào group docker,
   cấu hình log rotation + `metrics-addr` cho Docker daemon.
4. **nginx** — cài Nginx + Certbot (plugin nginx).

> Ansible **chỉ** chuẩn bị host. Nó không cài Jenkins, không deploy app/monitoring,
> không cấu hình virtual host cho domain — những việc đó nằm ở CI/CD và bước thủ
> công bên dưới.

## Bước 4 — Đưa repo + .env lên EC2 (một lần)

App được chạy bằng `docker-compose.yml` tại `/home/Mern-Todo-App` (source) trên EC2,
nạp env từ `/home/secrets/.env`. Clone repo vào `/home/Mern-Todo-App`, tạo
`/home/secrets/.env` từ `.env.ec2.example` và `chmod 600`.
Chi tiết: [../.claude/docs/production-ec2.md](../.claude/docs/production-ec2.md).

## Bước 5 — Cấu hình Nginx host + TLS

Dùng mẫu `../deploy/nginx/mern-todo.conf.example` (proxy `/`→3000, `/api/`→8000),
rồi cấp chứng chỉ:

```bash
sudo certbot --nginx -d <your-domain>
```

## Bước 6 — Triển khai app (CI/CD)

Deploy tự động bằng Jenkins (push nhánh `release/production` + commit `[tag]production`)
hoặc GitHub Actions (push git tag `production`). Xem
[../.claude/docs/cicd-pipeline.md](../.claude/docs/cicd-pipeline.md).

Truy cập sau khi deploy: `http://<IP>` (app), `:8080` (Jenkins), `:3001` (Grafana),
`:9090` (Prometheus).

## Grafana — Import dashboards (tùy chọn)

Datasource Prometheus đã được provision sẵn. Import dashboard qua UI:

| Dashboard | Import ID |
|---|---|
| Node Exporter Full (phần cứng) | `1860` |
| MongoDB (mongodb-exporter) | `7353` |
| Docker / cAdvisor | `893` |

**Dashboards → Import → nhập ID → chọn datasource Prometheus → Import.**

## Xóa hạ tầng sau khi nộp bài

```bash
cd infra/terraform
terraform destroy -auto-approve
```
