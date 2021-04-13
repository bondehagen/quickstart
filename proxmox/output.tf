
output "rancher_server_url" {
  value = module.rancher_common.rancher_url
}

output "rancher_node_ip" {
  value = proxmox_vm_qemu.rancher_server.default_ipv4_address
}

output "workload_node_ip" {
  value = proxmox_vm_qemu.quickstart_node.default_ipv4_address
}
