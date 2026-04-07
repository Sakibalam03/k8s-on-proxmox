# Download Ubuntu 24.04 LTS cloud image to Proxmox
# Note: The README uses Ubuntu 26.04 daily ISO; swap the URL in variables.tf
#       once a stable 26.04 cloud image is available.
resource "proxmox_virtual_environment_download_file" "ubuntu_cloud_image" {
  content_type = "iso"
  datastore_id = var.iso_storage
  node_name    = var.proxmox_node
  url          = var.ubuntu_cloud_image_url
  file_name    = "ubuntu-noble-cloudimg-amd64.img"
  overwrite    = false
}

# Cloud-init user data — applied to every node (master + workers).
# Installs all Kubernetes prerequisites: kernel modules, containerd, kubeadm/kubelet/kubectl.
resource "proxmox_virtual_environment_file" "cloud_init_user_data" {
  content_type = "snippets"
  datastore_id = var.iso_storage
  node_name    = var.proxmox_node

  source_raw {
    file_name = "k8s-cloud-init.yaml"
    data      = <<-EOF
      #cloud-config
      package_update: true
      package_upgrade: true

      packages:
        - qemu-guest-agent
        - curl
        - apt-transport-https
        - ca-certificates
        - gpg
        - containerd

      runcmd:
        # Enable guest agent
        - systemctl enable --now qemu-guest-agent

        # Disable swap (required by kubelet)
        - swapoff -a
        - sed -i '/\bswap\b/d' /etc/fstab

        # Load kernel modules
        - |
          cat <<MODULES > /etc/modules-load.d/k8s.conf
          overlay
          br_netfilter
          MODULES
        - modprobe overlay
        - modprobe br_netfilter

        # Sysctl for bridge / IP forwarding
        - |
          cat <<SYSCTL > /etc/sysctl.d/k8s.conf
          net.bridge.bridge-nf-call-iptables  = 1
          net.bridge.bridge-nf-call-ip6tables = 1
          net.ipv4.ip_forward                 = 1
          SYSCTL
        - sysctl --system

        # Configure containerd with SystemdCgroup = true
        - mkdir -p /etc/containerd
        - containerd config default > /etc/containerd/config.toml
        - sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
        - systemctl restart containerd
        - systemctl enable containerd

        # Add Kubernetes apt repository and install components
        - mkdir -p -m 755 /etc/apt/keyrings
        - curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
        - echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /' > /etc/apt/sources.list.d/kubernetes.list
        - apt-get update -y
        - apt-get install -y kubelet kubeadm kubectl
        - apt-mark hold kubelet kubeadm kubectl
    EOF
  }
}

# ─── Master Node (VM 200) ────────────────────────────────────────────────────

resource "proxmox_virtual_environment_vm" "k8s_master" {
  name      = "k8s-master"
  node_name = var.proxmox_node
  vm_id     = 200

  agent {
    enabled = true
  }

  cpu {
    cores   = 4
    sockets = 1
    type    = "host"
    numa    = false
  }

  memory {
    dedicated = 4096
    floating  = 0 # balloon disabled
  }

  network_device {
    bridge  = var.bridge
    model   = "virtio"
    vlan_id = var.vlan_tag
  }

  disk {
    datastore_id = var.storage_pool
    file_id      = proxmox_virtual_environment_download_file.ubuntu_cloud_image.id
    interface    = "scsi0"
    size         = 50
    discard      = "on"
    iothread     = true
    ssd          = true
    file_format  = "raw"
  }

  scsi_hardware = "virtio-scsi-single"

  boot_order = ["scsi0"]

  initialization {
    ip_config {
      ipv4 {
        address = "${var.master_ip}/24"
        gateway = var.gateway
      }
    }

    user_account {
      username = var.vm_username
      password = var.vm_password
      keys     = [var.ssh_public_key]
    }

    user_data_file_id = proxmox_virtual_environment_file.cloud_init_user_data.id
  }
}

# ─── Worker Nodes (VM 201, 202) ──────────────────────────────────────────────

resource "proxmox_virtual_environment_vm" "k8s_worker" {
  count     = length(var.worker_ips)
  name      = "k8s-worker${count.index + 1}"
  node_name = var.proxmox_node
  vm_id     = 201 + count.index

  agent {
    enabled = true
  }

  cpu {
    cores   = 2
    sockets = 1
    type    = "host"
    numa    = false
  }

  memory {
    dedicated = 2048
    floating  = 0
  }

  network_device {
    bridge  = var.bridge
    model   = "virtio"
    vlan_id = var.vlan_tag
  }

  disk {
    datastore_id = var.storage_pool
    file_id      = proxmox_virtual_environment_download_file.ubuntu_cloud_image.id
    interface    = "scsi0"
    size         = 50
    discard      = "on"
    iothread     = true
    ssd          = true
    file_format  = "raw"
  }

  scsi_hardware = "virtio-scsi-single"

  boot_order = ["scsi0"]

  initialization {
    ip_config {
      ipv4 {
        address = "${var.worker_ips[count.index]}/24"
        gateway = var.gateway
      }
    }

    user_account {
      username = var.vm_username
      password = var.vm_password
      keys     = [var.ssh_public_key]
    }

    user_data_file_id = proxmox_virtual_environment_file.cloud_init_user_data.id
  }
}
