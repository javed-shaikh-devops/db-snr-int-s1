# Enable required APIs
resource "google_project_service" "apis" {
  for_each = toset([
    "container.googleapis.com",
    "privateca.googleapis.com",
    "cloudkms.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com"
  ])

  project = var.project_id
  service = each.value
  disable_on_destroy = false
}

# Create custom service account for Private CA
resource "google_service_account" "cert-manager-cas-issuer-sa" {
  account_id   = "cert-manager-cas-issuer-sa"
  display_name = "Custom Private CA Service Account"
  project      = var.project_id
}

# Assign IAM roles to the custom service account
resource "google_project_iam_member" "privateca_requester" {
  for_each = toset([
    "roles/privateca.admin",
    "roles/privateca.certificateRequester",
    "roles/cloudkms.admin",
    "roles/iam.serviceAccountUser",
    "roles/viewer"
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.cert-manager-cas-issuer-sa.email}"
}

# Random suffix for names
resource "random_id" "suffix" {
  byte_length = 4
}

# CAS CA Pool
resource "google_privateca_ca_pool" "ca_pool" {
  name     = "ca-pool-${random_id.suffix.hex}"
  location = var.region
  tier     = "ENTERPRISE"
  publishing_options {
    publish_ca_cert = true
    publish_crl     = true
  }
  depends_on = [google_project_service.apis]
}

# Grant admin access on CA Pool
resource "google_privateca_ca_pool_iam_member" "ca_admin" {
  ca_pool = "projects/${var.project_id}/locations/${var.region}/caPools/${google_privateca_ca_pool.ca_pool.name}"
  role    = "roles/privateca.admin"
  member  = "serviceAccount:${google_service_account.cert-manager-cas-issuer-sa.email}"
  depends_on = [google_privateca_ca_pool.ca_pool]
}

# KMS Key Ring
resource "google_kms_key_ring" "cas_keyring" {
  name     = "cas-keyring-${random_id.suffix.hex}"
  location = var.region
  project  = var.project_id
}

# KMS CryptoKey
resource "google_kms_crypto_key" "cas_key" {
  name     = "cas-key"
  key_ring = google_kms_key_ring.cas_keyring.id
  purpose  = "ASYMMETRIC_SIGN"
  version_template {
    algorithm = "EC_SIGN_P384_SHA384"
  }
  lifecycle {
    prevent_destroy = true
  }
}

resource "null_resource" "create_cas_identity" {
  provisioner "local-exec" {
    command = "gcloud beta services identity create --service=privateca.googleapis.com --project=${var.project_id}"
  }
  depends_on = [google_project_service.apis]
}

# Get the current project number (required to construct the CAS SA email)
data "google_project" "current" {
  project_id = var.project_id
}

# Grant the CAS service account permission to view the public key in KMS
resource "google_kms_crypto_key_iam_member" "cas_key_public_view" {
  crypto_key_id = google_kms_crypto_key.cas_key.id
  role          = "roles/cloudkms.viewer"
  member        = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-privateca.iam.gserviceaccount.com"

  depends_on = [null_resource.create_cas_identity]
}

# IAM Bindings for KMS key
resource "google_kms_crypto_key_iam_binding" "cas_signer" {
  crypto_key_id = google_kms_crypto_key.cas_key.id
  role          = "roles/cloudkms.signerVerifier"
  members = [
    "serviceAccount:${google_service_account.cert-manager-cas-issuer-sa.email}",

  ]
}

resource "google_kms_crypto_key_iam_binding" "cas_viewer" {
  crypto_key_id = google_kms_crypto_key.cas_key.id
  role          = "roles/cloudkms.viewer"
  members = [
    "serviceAccount:${google_service_account.cert-manager-cas-issuer-sa.email}"
  ]
}

# Self-signed Root CA
resource "google_privateca_certificate_authority" "root_ca" {
  pool                     = google_privateca_ca_pool.ca_pool.name
  certificate_authority_id = "root-ca-${random_id.suffix.hex}"
  location                 = var.region
  deletion_protection      = false

  config {
    subject_config {
      subject {
        organization = var.organization_name
        common_name  = "Root CA"
      }
    }

    x509_config {
      ca_options {
        is_ca                 = true
        max_issuer_path_length = 10
      }

      key_usage {
        base_key_usage {
          cert_sign = true
          crl_sign  = true
        }
        extended_key_usage {
          server_auth = false
        }
      }
    }

  }

  key_spec {
    cloud_kms_key_version = "${google_kms_crypto_key.cas_key.id}/cryptoKeyVersions/1"
  }

  type          = "SELF_SIGNED"
  desired_state = "STAGED"

  depends_on = [
    google_kms_crypto_key_iam_binding.cas_signer,
    google_kms_crypto_key_iam_binding.cas_viewer,
    google_kms_crypto_key_iam_member.cas_key_public_view,
    google_project_iam_member.privateca_requester,
    google_privateca_ca_pool_iam_member.ca_admin,
    null_resource.create_cas_identity
  ]
  timeouts {
    create = "30m"
    delete = "30m"
  }
}

# Workload Identity Binding for cert-manager
resource "google_service_account_iam_member" "cert_manager_workload_identity" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${google_service_account.cert-manager-cas-issuer-sa.email}"
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[cert-manager/cert-manager]"
}

# GKE Cluster
resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.region

  remove_default_node_pool = true
  initial_node_count       = 1

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  depends_on = [google_project_service.apis]
  timeouts {
    create = "40m"
    delete = "20m"
    update = "20m"
  }
}

# Node Pool
resource "google_container_node_pool" "primary_nodes" {
  name       = "${var.cluster_name}-node-pool"
  location   = var.region
  cluster    = google_container_cluster.primary.name
  node_count = var.node_count

  node_config {
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]
    machine_type = var.machine_type
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}
