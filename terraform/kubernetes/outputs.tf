output "haproxy_ingress_namespace" {
  description = "Namespace where HAProxy ingress controller is deployed"
  value       = kubernetes_namespace.haproxy_controller.metadata[0].name
}

output "metallb_ip_range" {
  description = "IP range assigned to MetalLB"
  value       = var.metallb_ip_range
}

output "nginx_service_name" {
  description = "Name of the nginx test service"
  value       = var.deploy_nginx_test ? kubernetes_service_v1.nginx_test[0].metadata[0].name : null
}

output "verify_commands" {
  description = "Commands to verify the deployment"
  value       = <<-EOT
    # Check MetalLB pods
    kubectl get pods -n metallb-system

    # Check HAProxy ingress controller and its external IP
    kubectl get pods -n haproxy-controller
    kubectl get svc  -n haproxy-controller

    # Check nginx test service external IP
    kubectl get svc nginx-service

    # Test nginx via MetalLB IP (e.g. http://10.69.5.240)
    curl http://<EXTERNAL-IP>

    # Test via ingress (add to /etc/hosts: <haproxy-external-ip> nginx.lab.local)
    curl http://nginx.lab.local
  EOT
}
