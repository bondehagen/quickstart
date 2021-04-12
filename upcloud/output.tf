
output "rancher_server_url" {
  value = module.rancher_common.rancher_url
}

output "rancher_node_ip" {
  value = upcloud_server.rancher_server.network_interface[0].ip_address
}

output "workload_node_ip" {
  value = upcloud_server.quickstart_node.network_interface[0].ip_address
}
