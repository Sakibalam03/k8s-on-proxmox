# Kubernetes on Proxmox VE

---

## Network Configuration

In our lab setup we are using VLAN **67** with the `10.69.67.0/24` address range.
The DHCP scope covers `10.69.67.2` - `10.69.67.99`,
so any addresses from `10.69.67.100` to `10.69.67.254` can be assigned statically.

---

## 1. Creating Virtual Machines

We need to create 4 Linux Virtual Machines on Proxmox:

- **Master Node** — acts as cluster administrator (4 vCPU, 8 GB RAM)
- **Worker Node 1, 2 & 3** — the ones actually running containers (8 vCPU, 16 GB RAM each)

While any Linux kernel-based system can run Kubernetes, the easiest way to follow this guide is with Ubuntu or another Debian-based OS.

I will go for **Ubuntu Server 24.04 LTS** — go to [THIS LINK](https://ubuntu.com/download/server) to download the image.

1. Scroll down to the live server ISO file and click **'copy link address'**
2. Then click **'query link'** in Proxmox and download

> **Tip:** Optionally run 'Create VM' just to inspect the config file — you don't need to actually install the OS.
> I will create that VM with id of **101**.
>
> In the Proxmox console run:
> ```bash
> qm config 101
> ```
> It will show you the output of the `/etc/pve/qemu-server/101.conf` file.
> Run `man qm` to combine that output with the instructions for the `qm` command.

---

### VM Definitions

Note that the Master Node might need a bit more resources than Worker Nodes.

| Node | vCPU | RAM |
|------|------|-----|
| Master | 4 (2 cores × 2 sockets) | 8 GB |
| Worker | 8 (4 cores × 2 sockets) | 16 GB |

#### With rover-storage-main (external storage)

**Master Node (VM 200)**
```bash
qm create 200 \
  --name k8s-master \
  --agent 1 \
  --balloon 0 \
  --cores 2 \
  --sockets 2 \
  --cpu host \
  --memory 8192 \
  --numa 0 \
  --scsihw virtio-scsi-single \
  --net0 virtio,bridge=vmbr0,tag=67,firewall=0 \
  --vga qxl,clipboard=vnc,memory=32 \
  --onboot 1 \
  --ide2 local:iso/ubuntu-24.04.3-live-server-amd64.iso,media=cdrom \
  --boot "order=scsi0;ide2;net0" \
  --scsi0 rover-storage-main:200,discard=on,iothread=1,ssd=1
```

**Worker Node 1 (VM 201)**
```bash
qm create 201 \
  --name k8s-worker1 \
  --agent 1 \
  --balloon 0 \
  --cores 4 \
  --sockets 2 \
  --cpu host \
  --memory 16384 \
  --numa 0 \
  --scsihw virtio-scsi-single \
  --net0 virtio,bridge=vmbr0,tag=67,firewall=0 \
  --vga qxl,clipboard=vnc,memory=32 \
  --onboot 1 \
  --ide2 local:iso/ubuntu-24.04.3-live-server-amd64.iso,media=cdrom \
  --boot "order=scsi0;ide2;net0" \
  --scsi0 rover-storage-main:200,discard=on,iothread=1,ssd=1
```

**Worker Node 2 (VM 202)**
```bash
qm create 202 \
  --name k8s-worker2 \
  --agent 1 \
  --balloon 0 \
  --cores 4 \
  --sockets 2 \
  --cpu host \
  --memory 16384 \
  --numa 0 \
  --scsihw virtio-scsi-single \
  --net0 virtio,bridge=vmbr0,tag=67,firewall=0 \
  --vga qxl,clipboard=vnc,memory=32 \
  --onboot 1 \
  --ide2 local:iso/ubuntu-24.04.3-live-server-amd64.iso,media=cdrom \
  --boot "order=scsi0;ide2;net0" \
  --scsi0 rover-storage-main:200,discard=on,iothread=1,ssd=1
```

**Worker Node 3 (VM 203)**
```bash
qm create 203 \
  --name k8s-worker3 \
  --agent 1 \
  --balloon 0 \
  --cores 4 \
  --sockets 2 \
  --cpu host \
  --memory 16384 \
  --numa 0 \
  --scsihw virtio-scsi-single \
  --net0 virtio,bridge=vmbr0,tag=67,firewall=0 \
  --vga qxl,clipboard=vnc,memory=32 \
  --onboot 1 \
  --ide2 local:iso/ubuntu-24.04.3-live-server-amd64.iso,media=cdrom \
  --boot "order=scsi0;ide2;net0" \
  --scsi0 rover-storage-main:200,discard=on,iothread=1,ssd=1
```

#### With Default Proxmox Storage (local-lvm)

> Note that the above is true for my setup with a Transcend SSD used as external storage. For a default Proxmox setup the `qm` code might look more like this — you simply have to build it based on the output of your conf file, or go through the manual process of VM creation, whichever you find easier.

```bash
qm create 200 \
  --name k8s-master \
  --agent 1 \
  --balloon 0 \
  --cores 2 \
  --sockets 2 \
  --cpu host \
  --memory 8192 \
  --numa 0 \
  --scsihw virtio-scsi-single \
  --net0 virtio,bridge=vmbr0,tag=67,firewall=0 \
  --vga qxl,clipboard=vnc,memory=32 \
  --onboot 1 \
  --ide2 local:iso/ubuntu-24.04.3-live-server-amd64.iso,media=cdrom \
  --boot "order=scsi0;ide2;net0" \
  --scsi0 local-lvm:200,discard=on,iothread=1,ssd=1
```

---

## 2. Initial VM Setup

Now start each one and configure hostname and static IP address on them.

> If you wonder — yes, we could use cloud images / templates, or you could set up one instance and clone it, but those solutions are more confusing and for 3 VMs are not even quicker to set up. For cloned images you would need to remove machine IDs, re-provision SSH keys and more. Installing each instance might not look like the most efficient way, but it really does not take longer than other approaches.

Still in Proxmox, log on to each VM in the console using the user/pass you've just configured and run:

```bash
sudo apt update && sudo apt upgrade -y
```

Then when they finish, run:

```bash
sudo reboot
```

---

## 3. SSH & tmux Setup

Now SSH to each of them (can be from another device on the network that can also run tmux).
I will run on MAC — you simply run `brew install tmux` to install the tmux terminal multiplexer.

### Useful tmux commands

| Shortcut | Action |
|---|---|
| `^b + %` | Split screen vertically (Ctrl+B, then Shift+5) |
| `^b + "` | Split screen horizontally |
| `^b + arrows` | Switch between panes |
| `^b + x` | Close current session (prompts for confirmation) |
| `^d` | Close current tmux pane without warning |

We can run `tmux`, then `^b + "` to split the screen horizontally, then do it again so we have 3 sections.
SSH to worker 2 in the bottom window, then `^b + up arrow` to move to the pane above and SSH to worker 1, then up again to SSH to master.

`^b + :` opens **command mode**, where we can type `setw synchronize-panes` to run the same command in all panes simultaneously.

Now run:

```bash
sudo apt install qemu-guest-agent -y
```

Each command should now run for all VMs at the same time.

---

## 4. Kubernetes Prerequisites

### Disable Swap

We have to disable the swap file, as otherwise our kubelet service might behave unpredictably:

```bash
sudo swapoff -a
sudo nano /etc/fstab
```

Comment out the line with `swap.image`.

### Verify Hostnames

```bash
cat /etc/hostname   # check hostnames are set correctly
cat /etc/hosts      # check each has a host entry
```

### Load Kernel Modules

We need to load specific kernel modules for the overlay file system and bridged traffic:

```bash
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
```

If we run `cat /etc/modules-load.d/k8s.conf` we can see those 2 lines added to that k8s.conf file.
When your Linux system boots up, it reads all files in that directory and automatically loads the listed modules.
It ensures `overlay` (for containers) and `br_netfilter` (for bridge networking) are always present even after reboots.

Then load them into memory immediately without a reboot:

```bash
sudo modprobe overlay
sudo modprobe br_netfilter
```

> **overlay** — handles how containers see files (used by Docker/container images)
> **br_netfilter** — allows the Linux kernel to pass bridge (Layer 2) traffic to iptables (Layer 3) for processing; essentially lets containers talk to each other

### Configure Sysctl Parameters

Simply loading the modules isn't enough — you also have to tell the kernel to use them for IPv4 and IPv6 traffic:

```bash
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
```

Verify with `cat /etc/sysctl.d/k8s.conf` — you should see those 3 lines.
Apply to the running session with:

```bash
sudo sysctl --system
```

---

## 5. Install Container Runtime (containerd)

```bash
sudo apt install containerd -y
```

Run `systemctl status containerd` to verify the service is up and running.

Create the default configuration:

```bash
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
```

Check the value we need to change:

```bash
cat /etc/containerd/config.toml | grep SystemdCgroup
```

This value is currently `false` — we need it `true`:

```bash
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
```

Then restart and enable containerd:

```bash
sudo systemctl restart containerd
sudo systemctl enable containerd
sudo systemctl status containerd
```

You should see containerd both **active** and **enabled** (enabled means it will auto-start after reboot).

---

## 6. Install Kubernetes Components

These commands will install curl and gpg, add the necessary repositories, and install the packages:

```bash
sudo apt update && sudo apt install -y apt-transport-https ca-certificates curl gpg

# Download the public signing key
sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.35/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Add the repository
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.35/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
```

While `kubelet`, `kubeadm` and `kubectl` work together to run your cluster, they have very distinct jobs: one is the **worker**, one is the **installer**, and one is the **remote control**.

The `hold` command locks the current versions — this is advisable because a standard `apt upgrade` could accidentally update these components to a newer version incompatible with your cluster state. We might upgrade them periodically, but in a controlled way.

---

## 7. Initialize the Cluster

Optional — reboot all nodes first:

```bash
sudo reboot
```

Probably not necessary, but it's good practice after installing many new system components. Once rebooted, close the tmux session (`Ctrl + d`) and SSH to each instance separately.

### On the Master Node only

```bash
sudo kubeadm init --pod-network-cidr=10.244.0.0/16
```

> Best is to not fiddle with this IP prefix — it has nothing to do with our static DHCP scope (the only requirement is that this prefix can't be the same as the one on our network). This `10.244.0.0/16` prefix needs to match the CNI component we will install shortly. Since we are using **Flannel**, the easiest approach is to run this command exactly as-is.

This command generates a `join` command at the end that we will need for the worker nodes. Note that **this join command is valid for only 24 hours**. If you need to add a worker later, refresh it with:

```bash
kubeadm token create --print-join-command
```

### Configure kubectl

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

### Install CNI — Flannel

The CNI (Container Network Interface) creates the overlay network for communication inside the cluster. Without it, all nodes will show as `Not Ready`.

```bash
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
```

### Join Worker Nodes

Copy the join command generated on the master node and run it on each worker. It requires sudo:

```bash
sudo kubeadm join 10.69.67.200:6443 --token vyg76p.pz5k6dkrkaopvjhi --discovery-token-ca-cert-hash sha256:fb914ae294538ea1d35e18fab62df421f936dd68069eb877aa3b8e49634321a3
```

### Verify the Cluster

```bash
kubectl get nodes
```

You will see the ROLE for worker nodes is empty — that is expected with modern Kubernetes versions. The 'worker' role is simply assumed by default for any node that is not a master node.

**The cluster is working!** At this stage you can deploy services to your new Kubernetes cluster.

---

## 8. MetalLB — LoadBalancer Support

You will quickly notice one limitation: there is no `LoadBalancer` service type available out of the box. You can deploy services of type `NodePort` or use `HostNetwork`, but for a more cloud-like solution, we can add **MetalLB**.

First, enable strict ARP:

```bash
kubectl edit configmap -n kube-system kube-proxy
```

In `ipvs` you will see `strictARP` set to `false` — change it to `true`.
(For vim: press `i` to insert, make the change, then `Esc` and `:wq` to save.)

Install MetalLB:

```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.15.3/config/manifests/metallb-native.yaml
```

Verify the pods are running (may take a moment):

```bash
kubectl get pods -n metallb-system
```

You should see 4 pods running.

### Configure IP Address Pool

Create `proxmox-ip-pool.yaml` and paste the following. Remember to adjust the IP range to your desired range:

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: rdp-labs-pool
  namespace: metallb-system
spec:
  addresses:
  - 10.69.67.220-10.69.67.245 # CHANGE THIS to your desired range
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: layer2-advert
  namespace: metallb-system
spec:
  ipAddressPools:
  - rdp-labs-pool
```

Apply it:

```bash
kubectl apply -f proxmox-ip-pool.yaml
```

---

## 9. Testing — Deploy nginx

Create `nginx-test.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-test
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
spec:
  selector:
    app: nginx
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
  type: LoadBalancer
```

Deploy it:

```bash
kubectl apply -f nginx-test.yaml
```

Check the service:

```bash
kubectl get svc nginx-service
```

You should see both a cluster IP and an **external IP** assigned by MetalLB.
Just type that IP address in your browser (like `10.69.67.240` for me) and you should see **'Welcome to nginx'**.
It's the same as running `http://10.69.67.240:80`.

---

## 10. HAProxy Ingress Controller

An Ingress Controller allows you to route external HTTP/HTTPS traffic to services inside the cluster using hostnames and paths — a cleaner alternative to exposing every service via LoadBalancer.

### Install via Helm

First, install Helm if you haven't already:

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

Add the HAProxy Helm repository and install the ingress controller:

```bash
helm repo add haproxytech https://haproxytech.github.io/helm-charts
helm repo update

helm install haproxy-ingress haproxytech/kubernetes-ingress \
  --create-namespace \
  --namespace haproxy-controller \
  --set controller.service.type=LoadBalancer
```

By setting `controller.service.type=LoadBalancer`, MetalLB will assign it an external IP from your pool automatically.

Verify the controller is running:

```bash
kubectl get pods -n haproxy-controller
kubectl get svc -n haproxy-controller
```

You should see the `haproxy-ingress` service with an `EXTERNAL-IP` assigned from your MetalLB range.

### Example Ingress Resource

Once the controller is running, you can route traffic to your services using an `Ingress` resource. Create `ingress-example.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-ingress
  annotations:
    ingress.class: haproxy
spec:
  rules:
  - host: nginx.lab.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: nginx-service
            port:
              number: 80
```

Apply it:

```bash
kubectl apply -f ingress-example.yaml
```

Now requests to `http://nginx.lab.local` (with that hostname pointing to your HAProxy external IP in DNS or `/etc/hosts`) will be routed to the nginx service.

---

## 11. Kubernetes Web UI Dashboard

> **Note:** The official Kubernetes Dashboard is deprecated and unmaintained. Consider using [Headlamp](https://headlamp.dev/) as a modern alternative.

### Install via Helm

```bash
helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard \
  --create-namespace \
  --namespace kubernetes-dashboard
```

Verify the pods are running:

```bash
kubectl get pods -n kubernetes-dashboard
```

### Access the Dashboard

```bash
kubectl -n kubernetes-dashboard port-forward svc/kubernetes-dashboard-kong-proxy 8443:443
```

Then open **https://localhost:8443** in your browser.

> **Note:** This only works from the machine running the port-forward command. For remote access, you can forward through an SSH tunnel.

### Create a Service Account Token

Dashboard only supports Bearer Token authentication. Follow the [creating a sample user guide](https://github.com/kubernetes/dashboard/blob/master/docs/user/access-control/creating-sample-user.md) to generate a token.

> **Warning:** Sample users created this way have full admin privileges — use for lab/testing purposes only.

---

You can build any services you like and do whatever you want — it is now a fully functional Kubernetes cluster.
