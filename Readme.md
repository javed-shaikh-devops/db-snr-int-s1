Enables Required APIs

container.googleapis.com

privateca.googleapis.com

cloudkms.googleapis.com

cloudresourcemanager.googleapis.com

iam.googleapis.com

Creates the Private CA Workload Identity

Uses gcloud beta services identity create to enable the CAS identity.

Creates a Custom GCP Service Account

cert-manager-cas-issuer-sa@${project_id}.iam.gserviceaccount.com

Grants IAM Roles to That Service Account

roles/privateca.admin

roles/privateca.certificateRequester

roles/cloudkms.admin

roles/iam.serviceAccountUser

roles/viewer

Creates a CA Pool and Assigns IAM

The CA Pool exists (google_privateca_ca_pool.ca_pool)

Grants admin role on CA pool to the service account.

Creates KMS KeyRing and CryptoKey

Grants necessary KMS roles to the service account, CAS identity, and terraform-sa.

Creates a GKE Cluster with Workload Identity enabled

Enables workload_identity_config on the cluster.

Workload Identity Binding for cert-manager

Binds the Kubernetes SA cert-manager/cert-manager to the GCP SA cert-manager-cas-issuer-sa via IAM role roles/iam.workloadIdentityUser