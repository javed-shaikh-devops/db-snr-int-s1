# Output variables
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
  value       = google_service_account.privateca_service_account.email
}

data "google_project" "project" {
  project_id = var.project_id
}

output "ca_pool_id" {
  value = google_privateca_ca_pool.ca_pool.id
}
output "service_account_email" {
  value = google_service_account.privateca_service_account.email
}