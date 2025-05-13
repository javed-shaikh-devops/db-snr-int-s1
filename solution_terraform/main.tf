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

# Get project number for service account
data "google_project" "current" {}

# Create custom service account for Private CA
resource "google_service_account" "privateca_service_account" {
  account_id   = "privateca-custom-sa"
  display_name = "Custom Private CA Service Account"
  project      = var.project_id
}

# Assign IAM roles to the custom service account for Private CA
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
  member  = "serviceAccount:${google_service_account.privateca_service_account.email}"
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
  depends_on = [google_project_service.apis]
}

resource "null_resource" "wait_for_cas_sa" {
  provisioner "local-exec" {
    command = "sleep 60"
  }
  depends_on = [google_privateca_ca_pool.ca_pool]
}

resource "google_privateca_ca_pool_iam_member" "ca_admin" {
  ca_pool = "projects/${var.project_id}/locations/${var.region}/caPools/${google_privateca_ca_pool.ca_pool.name}"
  role    = "roles/privateca.admin"
  member  = "serviceAccount:${google_service_account.privateca_service_account.email}"

  depends_on = [google_privateca_ca_pool.ca_pool, google_service_account.privateca_service_account]  # Explicit dependency
}

# Create KMS resources
resource "google_kms_key_ring" "cas_keyring" {
  name     = "cas-keyring-8"
  location = var.region
  project  = var.project_id
  depends_on = [google_project_service.apis]
}

resource "google_kms_crypto_key" "cas_key" {
  name            = "cas-key"
  key_ring        = google_kms_key_ring.cas_keyring.id
  purpose         = "ASYMMETRIC_SIGN"
  version_template {
    algorithm = "EC_SIGN_P384_SHA384"  # Recommended for CAS
  }

  lifecycle {
    prevent_destroy = true  # Should be true in production
  }
}


# Bind IAM role for the custom service account on the KMS key
resource "google_kms_crypto_key_iam_binding" "cas_signer" {
  crypto_key_id = google_kms_crypto_key.cas_key.id
  role          = "roles/cloudkms.signerVerifier"
  members = [
    "serviceAccount:${google_service_account.privateca_service_account.email}",
    "serviceAccount:service-${data.google_project.current.number}@gcp-sa-privateca.iam.gserviceaccount.com"
  ]
}

resource "google_kms_crypto_key_iam_binding" "cas_viewer" {
  crypto_key_id = google_kms_crypto_key.cas_key.id
  role          = "roles/viewer"
  members = [
    "serviceAccount:${google_service_account.privateca_service_account.email}"
  ]
}


resource "google_privateca_certificate_authority" "root_ca" {
  pool                     = google_privateca_ca_pool.ca_pool.name
  certificate_authority_id = "root-ca-${random_id.suffix.hex}"
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
    cloud_kms_key_version = "${google_kms_crypto_key.cas_key.id}/cryptoKeyVersions/1"
  }

  type = "SELF_SIGNED"
  desired_state = "ENABLED"
  depends_on = [
    google_kms_crypto_key_iam_binding.cas_signer,
    google_kms_crypto_key_iam_binding.cas_viewer,
    google_project_iam_member.privateca_requester,
    google_privateca_ca_pool_iam_member.ca_admin,
    null_resource.wait_for_cas_sa
  ]
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

  remove_default_node_pool = true
  initial_node_count       = 1

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  depends_on = [google_project_service.apis]  # Ensures APIs are enabled before creating the cluster
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

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}