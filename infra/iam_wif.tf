# Read-only reviewer access for Commit's Google Cloud evaluation team (Google Group).
resource "google_project_iam_member" "commit_reviewer" {
  project = var.project_id
  role    = "roles/viewer"
  member  = "group:${var.reviewer_email}"
}

# Keyless GitHub Actions authentication via Workload Identity Federation (replaces static JSON keys).
resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "meridian-github-pool"
  display_name              = "Meridian GitHub Actions Pool"
  description               = "OIDC identity pool for GitHub Actions Terraform CI (zero static JSON keys)."

  depends_on = [google_project_service.apis]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-actions"
  display_name                       = "GitHub Actions OIDC Provider"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
    "attribute.event_name" = "assertion.event_name"
  }

  # Strict repository + PR event lock: prevents any other repo or non-PR workflow from using this read-only plan SA.
  attribute_condition = "assertion.repository == '${var.github_repo}' && assertion.event_name == 'pull_request'"
}

resource "google_service_account" "tf_plan" {
  account_id   = "meridian-tf-plan-sa"
  display_name = "Terraform PR Plan Read-Only SA"
  description  = "Keyless CI service account for running terraform plan on pull requests."

  depends_on = [google_project_service.apis]
}

resource "google_service_account_iam_member" "wif_tf_plan_binding" {
  service_account_id = google_service_account.tf_plan.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repo}"
}

# Read-only project roles required to refresh Terraform state during `terraform plan`.
resource "google_project_iam_member" "tf_plan_viewer" {
  project = var.project_id
  role    = "roles/viewer"
  member  = "serviceAccount:${google_service_account.tf_plan.email}"
}

resource "google_project_iam_member" "tf_plan_security_reviewer" {
  project = var.project_id
  role    = "roles/iam.securityReviewer"
  member  = "serviceAccount:${google_service_account.tf_plan.email}"
}

resource "google_project_iam_member" "tf_plan_secret_viewer" {
  project = var.project_id
  role    = "roles/secretmanager.viewer"
  member  = "serviceAccount:${google_service_account.tf_plan.email}"
}

# Scoped exclusively to the Terraform state bucket with objectUser (no bucket IAM/ACL admin) for state locking.
resource "google_storage_bucket_iam_member" "tf_plan_state_bucket" {
  bucket = var.state_bucket_name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.tf_plan.email}"
}
