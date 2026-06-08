[mta]
${project}-server ansible_host=${server_ip} ansible_user=ubuntu ansible_ssh_private_key_file=${ssh_key} ansible_ssh_common_args='-o StrictHostKeyChecking=no'

[mta:vars]
ansible_python_interpreter=/usr/bin/python3
