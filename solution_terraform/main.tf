# Create a custom service account for Private CA
resource "google_service_account" "privateca_service_account" {
  account_id   = "privateca-custom-sa"
  display_name = "Custom Private CA Service Account"
  project      = var.project_id
}

# Bind the required IAM role for Private CA to the custom service account
resource "google_project_iam_member" "privateca_requester" {
  project = var.project_id
  role    = "roles/privateca.certificateRequester"
  member  = "serviceAccount:${google_service_account.privateca_service_account.email}"
}

# Assign 'roles/privateca.certificateAuthorityAdmin' to the custom service account
resource "google_project_iam_member" "privateca_admin" {
  project = var.project_id
  role    = "roles/privateca.certificateAuthorityAdmin"
  member  = "serviceAccount:${google_service_account.privateca_service_account.email}"
}

# Create KMS resources
resource "google_kms_key_ring" "cas_keyring_3" {
  name     = "cas-keyring-3"
  location = var.region
  project  = var.project_id
}

resource "google_kms_crypto_key" "cas_key_3" {
  name            = "cas-key-3"
  key_ring        = google_kms_key_ring.cas_keyring_3.id
  purpose         = "ASYMMETRIC_SIGN"
  version_template {
    algorithm = "EC_SIGN_P384_SHA384"  # Recommended for CAS
  }

  lifecycle {
    prevent_destroy = false  # Should be true in production
  }
}

# Bind IAM role for the custom service account on the KMS key
resource "google_kms_crypto_key_iam_binding" "cas_signer" {
  crypto_key_id = google_kms_crypto_key.cas_key_3.id
  role          = "roles/cloudkms.signerVerifier"
  members = [
    "serviceAccount:${google_service_account.privateca_service_account.email}"
  ]
}

# CAS resources (Private CA Pool and Root CA)
resource "random_id" "suffix" {
  byte_length = 4
}

resource "google_privateca_ca_pool" "ca_pool" {
  name     = "ca-pool-${random_id.suffix.hex}"
  location = var.region
  tier     = "ENTERPRISE"
  publishing_options {
    publish_ca_cert = true
    publish_crl     = true
  }
}

resource "google_privateca_certificate_authority" "root_ca" {
  pool                     = google_privateca_ca_pool.ca_pool.name
  certificate_authority_id = "root-ca"
  location                 = var.region
  deletion_protection      = false # Set to true for production

  config {
    subject_config {
      subject {
        organization = var.organization_name
        common_name = "Root CA"
      }
    }

    x509_config {
      ca_options {
        is_ca = true
        max_issuer_path_length = 10  # Max path length for root CAs
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
    cloud_kms_key_version = google_kms_crypto_key.cas_key_3.id
  }

  type = "SELF_SIGNED"
}

# Workload Identity for cert-manager
resource "google_service_account_iam_member" "cert_manager_workload_identity" {
  service_account_id = google_service_account.privateca_service_account.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[cert-manager/cert-manager]"
}

# Create GKE cluster with Workload Identity
resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.region

  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it.
  remove_default_node_pool = true
  initial_node_count       = 1

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  depends_on = [google_project_service.apis]
}

resource "google_container_node_pool" "primary_nodes" {
  name       = "${var.cluster_name}-node-pool"
  location   = var.region
  cluster    = google_container_cluster.primary.name
  node_count = var.node_count

  node_config {
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
    machine_type = var.machine_type

    # Workload Identity configuration
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}