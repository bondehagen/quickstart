provider "proxmox" {
  pm_api_url      = "https://${var.pm_ip}:8006/api2/json"
  pm_user         = var.pm_user
  pm_password     = var.pm_password
  pm_tls_insecure = "true"
}
provider "tls" {
}
provider "cloudinit" {
}