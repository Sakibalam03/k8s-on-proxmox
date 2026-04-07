# Proxmox connection
variable "proxmox_endpoint" {
  description = "Proxmox API endpoint URL (e.g. https://192.168.1.10:8006)"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox API token in the format user@realm!token-name=secret"
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "Skip TLS verification (set true for self-signed certs)"
  type        = bool
  default     = true
}

variable "proxmox_ssh_username" {
  description = "SSH username for Proxmox node (used by bpg provider for file uploads)"
  type        = string
  default     = "root"
}

variable "proxmox_node" {
  description = "Proxmox node name to deploy VMs on"
  type        = string
  default     = "pve"
}

# Storage
variable "storage_pool" {
  description = "Proxmox storage pool for VM disks (e.g. transcend or local-lvm)"
  type        = string
  default     = "local-lvm"
}

variable "iso_storage" {
  description = "Proxmox storage for ISO/image downloads"
  type        = string
  default     = "local"
}

# Network
variable "vlan_tag" {
  description = "VLAN tag for VM network interfaces"
  type        = number
  default     = 5
}

variable "bridge" {
  description = "Proxmox network bridge"
  type        = string
  default     = "vmbr0"
}

variable "gateway" {
  description = "Default gateway for VMs"
  type        = string
  default     = "10.69.5.1"
}

variable "master_ip" {
  description = "Static IP for the master node"
  type        = string
  default     = "10.69.5.200"
}

variable "worker_ips" {
  description = "Static IPs for worker nodes"
  type        = list(string)
  default     = ["10.69.5.201", "10.69.5.202"]
}

# VM credentials
variable "vm_username" {
  description = "Username created on each VM via cloud-init"
  type        = string
  default     = "ubuntu"
}

variable "vm_password" {
  description = "Password for the VM user (hashed with mkpasswd or plain for testing)"
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  description = "SSH public key to inject into VMs"
  type        = string
}

# Ubuntu cloud image
variable "ubuntu_cloud_image_url" {
  description = "URL for Ubuntu cloud image"
  type        = string
  default     = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}
