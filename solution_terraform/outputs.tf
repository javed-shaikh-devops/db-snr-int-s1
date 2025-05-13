output "ca_pool_name" {
  description = "The name of the CA Pool"
  value       = google_privateca_ca_pool.ca_pool.name
}

output "cluster_name" {
  description = "The name of the GKE cluster"
  value       = google_container_cluster.primary.name
}

output "cluster_endpoint" {
  description = "The endpoint of the GKE cluster"
  value       = google_container_cluster.primary.endpoint
}

output "cert_manager_sa_email" {
  description = "The email of the cert-manager service account"
  value       = google_service_account.cert-manager-cas-issuer-sa.email
}