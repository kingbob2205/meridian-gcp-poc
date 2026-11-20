resource "google_artifact_registry_repository" "api" {
  location      = var.region
  repository_id = "meridian-api"
  description   = "Container images for Meridian Payments POC API"
  format        = "DOCKER"

  cleanup_policies {
    id     = "keep-recent"
    action = "KEEP"
    most_recent_versions {
      keep_count = 5
    }
  }

  depends_on = [google_project_service.apis]
}

resource "google_service_account" "api" {
  account_id   = "meridian-api-sa"
  display_name = "Meridian API Cloud Run Runtime SA"
  description  = "Dedicated least-privilege runtime identity for Meridian Cloud Run API."

  depends_on = [google_project_service.apis]
}

resource "google_project_iam_member" "api_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.api.email}"
}

resource "google_project_iam_member" "api_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.api.email}"
}

resource "google_cloud_run_v2_service" "api" {
  name                = "meridian-api"
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_ALL" # Production: INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER + Cloud Armor WAF.
  deletion_protection = false

  template {
    service_account = google_service_account.api.email

    scaling {
      min_instance_count = 0
      max_instance_count = 3
    }

    vpc_access {
      network_interfaces {
        network    = google_compute_network.main.name
        subnetwork = google_compute_subnetwork.app.name
        tags       = ["meridian-api"]
      }
      egress = "PRIVATE_RANGES_ONLY"
    }

    containers {
      image = var.image_uri

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "256Mi"
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      env {
        name  = "CANDIDATE_NAME"
        value = var.candidate_name
      }
      env {
        name  = "DEPLOY_REGION"
        value = var.region
      }
      env {
        name  = "GIT_COMMIT"
        value = var.git_sha
      }
      env {
        name  = "DB_HOST"
        value = google_compute_address.sql_psc_ip.address
      }
      env {
        name  = "DB_PORT"
        value = "5432"
      }
      env {
        name  = "DB_NAME"
        value = google_sql_database.meridian.name
      }
      env {
        name  = "DB_USER"
        value = google_sql_user.app.name
      }
      env {
        name  = "SECRET_DB_PASSWORD_RESOURCE"
        value = "${google_secret_manager_secret.db_password.id}/versions/latest"
      }
      env {
        name  = "SECRET_API_TOKEN_RESOURCE"
        value = "${google_secret_manager_secret.third_party_api_token.id}/versions/latest"
      }

      startup_probe {
        tcp_socket {
          port = 8080
        }
        initial_delay_seconds = 1
        period_seconds        = 5
        failure_threshold     = 3
      }
    }
  }

  labels = {
    env        = "poc"
    workload   = "meridian-payments"
    managed_by = "terraform"
  }

  depends_on = [
    google_project_service.apis,
    google_compute_forwarding_rule.sql_psc_endpoint,
    google_compute_firewall.allow_egress_sql_psc,
    google_sql_user.app,
    google_secret_manager_secret_version.db_password,
    google_secret_manager_secret_version.third_party_api_token,
    google_secret_manager_secret_iam_member.api_db_password_accessor,
    google_secret_manager_secret_iam_member.api_token_accessor,
  ]
}

# Public invoker enabled strictly to expose the evaluation GET /health contract.
resource "google_cloud_run_v2_service_iam_member" "public_invoker" {
  project  = var.project_id
  location = google_cloud_run_v2_service.api.location
  name     = google_cloud_run_v2_service.api.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
