output "server_ip" {
  description = "Public IP of server"
  value       = aws_instance.mta.public_ip
}

output "instance_id" {
  description = "EC2 Instance ID"
  value       = aws_instance.mta.id
}

output "ssh_command" {
  description = "SSH Command to connect to the server"
  value       = "ssh -i ${var.ssh_private_key_path} ubuntu@${aws_instance.mta.public_ip}"
}

output "jenkins_url" {
  description = "URL to access Jenkins"
  value       = "http://${aws_instance.mta.public_ip}:8080"
}

output "grafana_url" {
  description = "URL to access Grafana"
  value       = "http://${aws_instance.mta.public_ip}:3001"
}

output "app_url" {
  description = "URL to access the application"
  value       = "http://${aws_instance.mta.public_ip}"
}

output "next_step" {
  description = "Next step: run Ansible"
  value       = "cd ../ansible && ansible-playbook -i inventory.ini playbooks/site.yml"
}
