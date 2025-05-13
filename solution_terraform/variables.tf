variable "project_id" {
  description = "The GCP project ID"
  type        = string
  default     = "db-demo-int"
}

variable "region" {
  description = "The GCP region"
  type        = string
  default     = "europe-west2"
}

variable "cluster_name" {
  description = "The name of the GKE cluster"
  type        = string
  default     = "istio-cas-demo"
}

variable "node_count" {
  description = "Number of nodes in the cluster"
  type        = number
  default     = 1
}

variable "machine_type" {
  description = "Machine type for GKE nodes"
  type        = string
  default     = "e2-small"
}

variable "organization_name" {
  description = "Organization name for CA certificate"
  type        = string
  default     = "DB Demo"
}

variable "network" {
  type        = string
  description = "VPC network for the cluster"
}

variable "subnetwork" {
  type        = string
  description = "Subnetwork for the cluster"
}