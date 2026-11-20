output "service_url" {
  description = "Public Cloud Run service URL."
  value       = google_cloud_run_v2_service.api.uri
}

output "health_url" {
  description = "Live GET /health contract URL."
  value       = "${google_cloud_run_v2_service.api.uri}/health"
}

output "sql_instance_name" {
  description = "Private-only Cloud SQL PostgreSQL instance name."
  value       = google_sql_database_instance.postgres.name
}

output "sql_psc_ip" {
  description = "Internal PSC endpoint IP inside meridian-vpc."
  value       = google_compute_address.sql_psc_ip.address
}

output "artifact_registry_repo" {
  description = "Artifact Registry Docker repository path."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.api.repository_id}"
}

output "wif_provider_name" {
  description = "Workload Identity Provider resource name for GitHub Actions."
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "tf_plan_sa_email" {
  description = "Read-only Terraform plan Service Account email."
  value       = google_service_account.tf_plan.email
}
