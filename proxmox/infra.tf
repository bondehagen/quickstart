# Proxmox infrastructure resources

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

data "cloudinit_config" "user" {
  gzip          = false
  base64_encode = false
  boundary      = "//"
  part {
    content_type = "text/cloud-config"
    content = templatefile(
      join("/", [path.module, "user-data.cfg"]),
      {
        sshkey   = tls_private_key.global_key.public_key_openssh
        username = local.node_username
      }
    )
  }
  part {
    content_type = "text/x-shellscript"
    content = templatefile(
      join("/", [path.module, "../cloud-common/files/userdata_rancher_server.template"]),
      {
        docker_version = var.docker_version
        username       = local.node_username
      }
    )
  }
}

# Transfer the file to the Proxmox Host
resource "null_resource" "rancher_user_data_script" {
  provisioner "file" {
    content     = data.cloudinit_config.user.rendered
    destination = "/var/lib/vz/snippets/rancher_user_data_files"

    connection {
      type     = "ssh"
      user     = "root"
      password = var.pm_password
      host     = var.pm_ip
      agent    = false
    }
  }
}

resource "proxmox_vm_qemu" "rancher_server" {
  depends_on = [
    null_resource.rancher_user_data_script
  ]
  name        = "${var.prefix}-rancher-server"
  target_node = var.pm_node
  clone       = "ubuntu-bionic-template"
  os_type     = "cloud-init"
  agent       = 1
  cores       = 4
  memory      = 4096
  scsihw      = "virtio-scsi-pci"
  bootdisk    = "scsi0"
  disk {
    size    = "20G"
    type    = "scsi"
    storage = "local-lvm"
  }
  network {
    model  = "virtio"
    bridge = "vmbr0"
  }
  network {
    model  = "virtio"
    bridge = "vmbr0"
  }

  # Cloud Init Settings
  ipconfig0 = "ip=192.168.1.150/24,gw=192.168.1.1"
  ipconfig1 = "ip=192.168.1.160/24,gw=192.168.1.1"

  cicustom = "user=local:snippets/rancher_user_data_files"

  provisioner "remote-exec" {
    inline = [
      "echo 'Waiting for cloud-init to complete...'",
      "cloud-init status --wait > /dev/null",
      "echo 'Completed cloud-init!'",
      "echo 'Waiting for docker to start...'",
      "sudo /bin/bash -c 'while [[ -z \"$(! docker stats --no-stream 2> /dev/null)\" ]]; do sleep 2; done'",
      "echo 'Docker running'"
    ]
    connection {
      type        = "ssh"
      host        = self.ssh_host
      user        = local.node_username
      private_key = tls_private_key.global_key.private_key_pem
      agent       = false
      timeout     = "30s"
    }
  }
}

# Rancher resources
module "rancher_common" {
  source = "../rancher-common"

  node_public_ip         = proxmox_vm_qemu.rancher_server.default_ipv4_address
  node_internal_ip       = "192.168.1.160"
  node_username          = local.node_username
  ssh_private_key_pem    = tls_private_key.global_key.private_key_pem
  rke_kubernetes_version = var.rke_kubernetes_version

  cert_manager_version = var.cert_manager_version
  rancher_version      = var.rancher_version

  rancher_server_dns = join(".", ["rancher", proxmox_vm_qemu.rancher_server.default_ipv4_address, "xip.io"])
  admin_password     = var.rancher_server_admin_password

  workload_kubernetes_version = var.workload_kubernetes_version
  workload_cluster_name       = "quickstart-custom"
}

data "cloudinit_config" "worker_user" {
  gzip          = false
  base64_encode = false
  boundary      = "//"
  part {
    content_type = "text/cloud-config"
    content = templatefile(
      join("/", [path.module, "user-data.cfg"]),
      {
        sshkey   = tls_private_key.global_key.public_key_openssh
        username = local.node_username
      }
    )
  }
  part {
    content_type = "text/x-shellscript"
    content = templatefile(
      join("/", [path.module, "../cloud-common/files/userdata_quickstart_node.template"]),
      {
        docker_version   = var.docker_version
        username         = local.node_username
        register_command = module.rancher_common.custom_cluster_command
      }
    )
  }
}

# Transfer the file to the Proxmox Host
resource "null_resource" "worker_user_data_script" {
  provisioner "file" {
    content     = data.cloudinit_config.worker_user.rendered
    destination = "/var/lib/vz/snippets/worker_user_data_files"

    connection {
      type     = "ssh"
      user     = "root"
      password = var.pm_password
      host     = var.pm_ip
      agent    = false
    }
  }
}

# creating a single node workload cluster
resource "proxmox_vm_qemu" "quickstart_node" {
  depends_on = [
    null_resource.worker_user_data_script
  ]
  name        = "${var.prefix}-quickstart-node"
  clone       = "ubuntu-bionic-template"
  target_node = var.pm_node
  os_type     = "cloud-init"
  agent       = 1
  cores       = 2
  memory      = 4096
  scsihw      = "virtio-scsi-pci"
  bootdisk    = "scsi0"
  disk {
    size    = "20G"
    type    = "scsi"
    storage = "local-lvm"
  }
  network {
    model  = "virtio"
    bridge = "vmbr0"
  }
  network {
    model  = "virtio"
    bridge = "vmbr0"
  }

  # Cloud Init Settings
  ipconfig0 = "ip=192.168.1.151/24,gw=192.168.1.1"
  ipconfig1 = "ip=192.168.1.161/24,gw=192.168.1.1"

  cicustom = "user=local:snippets/worker_user_data_files"

  provisioner "remote-exec" {
    inline = [
      "echo 'Waiting for cloud-init to complete...'",
      "cloud-init status --wait > /dev/null",
      "echo 'Completed cloud-init!'",
    ]

    connection {
      type        = "ssh"
      host        = self.ssh_host
      user        = local.node_username
      private_key = tls_private_key.global_key.private_key_pem
    }
  }
}
