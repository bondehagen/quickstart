resource "tls_private_key" "global_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "local_file" "ssh_private_key_pem" {
  filename          = "${path.module}/id_rsa"
  sensitive_content = tls_private_key.global_key.private_key_pem
  file_permission   = "0600"
}

resource "local_file" "ssh_public_key_openssh" {
  filename = "${path.module}/id_rsa.pub"
  content  = tls_private_key.global_key.public_key_openssh
}

resource "upcloud_server" "rancher_server" {
  hostname = "rancher"
  zone     = "nl-ams1"
  plan     = "4xCPU-8GB"
  metadata = true

  template {
    size    = 50
    storage = "01000000-0000-4000-8000-000030200200"
  }

  user_data = templatefile(
    join("/", [path.module, "../cloud-common/files/userdata_rancher_server.template"]),
    {
      docker_version = var.docker_version
      username       = local.node_username
    }
  )

  # Network interfaces
  network_interface {
    type = "public"
  }

  network_interface {
    type = "utility"
  }

  # Include at least one public SSH key
  login {
    user = local.node_username
    keys = [replace(tls_private_key.global_key.public_key_openssh, "\n", "")]
    create_password   = false
    password_delivery = "none"
  }

  # Configuring connection details
  connection {
    type        = "ssh"
    host        = self.network_interface[0].ip_address
    user        = local.node_username
    private_key = tls_private_key.global_key.private_key_pem
   # agent = true
  }

  # Remotely executing a command on the server
  provisioner "remote-exec" {
    inline = [
      "echo 'Waiting for docker to start...'",
      "/bin/bash -c 'while [[ -z \"$(! docker stats --no-stream 2> /dev/null)\" ]]; do sleep 2; done'",
      "echo 'Docker running'",
    ]
  }
}


# Rancher resources
module "rancher_common" {
  source = "../rancher-common"

  node_public_ip         = upcloud_server.rancher_server.network_interface[0].ip_address
  node_internal_ip       = upcloud_server.rancher_server.network_interface[1].ip_address
  node_username          = local.node_username
  ssh_private_key_pem    = tls_private_key.global_key.private_key_pem
  rke_kubernetes_version = var.rke_kubernetes_version

  cert_manager_version = var.cert_manager_version
  rancher_version      = var.rancher_version

  rancher_server_dns = join(".", ["rancher", upcloud_server.rancher_server.network_interface[0].ip_address, "xip.io"])
  admin_password     = var.rancher_server_admin_password

  workload_kubernetes_version = var.workload_kubernetes_version
  workload_cluster_name       = "quickstart-upcloud-custom"
}

resource "upcloud_server" "quickstart_node" {
  hostname = "workload-node"
  zone     = "nl-ams1"
  plan     = "4xCPU-8GB"
  metadata = true

  template {
    size    = 50
    storage = "01000000-0000-4000-8000-000030200200"
  }

  # Network interfaces
  network_interface {
    type = "public"
  }

  network_interface {
    type = "utility"
  }

  user_data = templatefile(
    join("/", [path.module, "../cloud-common/files/userdata_quickstart_node.template"]),
    {
      docker_version   = var.docker_version
      username         = local.node_username
      register_command = module.rancher_common.custom_cluster_command
    }
  )

  # Include at least one public SSH key
  login {
    user = local.node_username
    keys = [replace(tls_private_key.global_key.public_key_openssh, "\n", "")]
    create_password   = false
    password_delivery = "none"
  }

  # Configuring connection details
  connection {
    type        = "ssh"
    host        = self.network_interface[0].ip_address
    user        = local.node_username
    private_key = tls_private_key.global_key.private_key_pem
  }

  # Remotely executing a command on the server
  provisioner "remote-exec" {
    inline = [
      "echo 'Waiting for docker to start...'",
      "/bin/bash -c 'while [[ -z \"$(! docker stats --no-stream 2> /dev/null)\" ]]; do sleep 2; done'",
      "echo 'Docker running'",
    ]
  }
}