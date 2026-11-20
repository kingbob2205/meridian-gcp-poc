variable "project_id" {
  description = "Dedicated isolated GCP project ID for the Meridian Payments POC."
  type        = string
  default     = "meridian-gcp-poc-ho26"
}

variable "region" {
  description = "EU GCP region (GDPR/PCI-DSS data residency). Frankfurt serves Germany & Lithuania."
  type        = string
  default     = "europe-west3"
}

variable "state_bucket_name" {
  description = "GCS bucket holding Terraform remote state (bootstrapped once by scripts/bootstrap.sh)."
  type        = string
  default     = "meridian-gcp-poc-ho26-tfstate"
}

variable "candidate_name" {
  description = "Candidate full name returned by GET /health."
  type        = string
  default     = "Hazav Ogdan"
}

variable "image_uri" {
  description = "Container image URI in Artifact Registry to deploy on Cloud Run."
  type        = string
}

variable "git_sha" {
  description = "Short Git SHA of the deployed commit returned by GET /health."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository (owner/repo) authorized via Workload Identity Federation."
  type        = string
  default     = "kingbob2205/meridian-gcp-poc"
}

variable "reviewer_email" {
  description = "Commit reviewer Google identity granted read-only Project Viewer access."
  type        = string
  default     = "gcp-hr@comm-it.cloud"
}
