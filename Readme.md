# Google CAS with GKE Integration

Terraform modules for deploying a Private Certificate Authority (CAS) with GKE integration, designed to work with cert-manager via Helm.

## 📦 Modules Overview

### 1. GKE Cluster
- Creates a GKE cluster with Workload Identity enabled
- Configures a default node pool with recommended settings

### 2. Private CA
- Provisions a Private CA pool with root CA
- Sets up KMS keys for certificate signing
- Configures CA publishing options

### 3. IAM
- Creates dedicated service account for cert-manager
- Configures least-privilege IAM roles
- Establishes Workload Identity binding

## 🚀 Deployment Workflow

### Prerequisites
- Google Cloud Project with billing enabled
- `gcloud` CLI authenticated
- Terraform v1.0+
- Helm v3.8+

## 📂 File Structure

├── main.tf # Root module configuration

├── variables.tf # Root variables

├── outputs.tf # Output values

├── helm-values.yaml.tftpl # Helm values template

├── modules/

│ ├── gke/ # GKE Cluster Module

│ │ ├── main.tf # Cluster and node pool resources

│ │ ├── variables.tf # Module-specific variables

│ │ └── outputs.tf # Cluster outputs (endpoint, kubeconfig)

│ ├── privateca/ # Private CA Module

│ │ ├── main.tf # CA Pool and Root CA

│ │ ├── kms.tf # KMS key configuration

│ │ ├── variables.tf # Module variables

│ │ └── outputs.tf # CA Pool name output

│ └── iam/ # IAM Module

│ ├── main.tf # Service accounts and IAM bindings

│ ├── variables.tf # IAM variables

│ └── outputs.tf # Service account email output

└── README.md # This documentation

### Installation
```bash

# Initialize Terraform
terraform init

# Plan Terraform 
terraform plan \ 
  -var="project_id=your-project-id" \
  -var="region=region-name"

# Deploy infrastructure
terraform apply \
  -var="project_id=your-project-id" \
  -var="region=region-name"