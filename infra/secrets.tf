resource "random_password" "third_party_api_token" {
  length  = 40
  special = false
}

# Replicated strictly in europe-west3 (user_managed) to honor EU data residency.
resource "google_secret_manager_secret" "db_password" {
  secret_id = "meridian-db-password"

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }

  labels = {
    env        = "poc"
    workload   = "meridian-payments"
    managed_by = "terraform"
  }

  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "db_password" {
  secret                 = google_secret_manager_secret.db_password.id
  secret_data_wo         = random_password.db_password.result
  secret_data_wo_version = 1
}

resource "google_secret_manager_secret" "third_party_api_token" {
  secret_id = "meridian-third-party-api-token"

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }

  labels = {
    env        = "poc"
    workload   = "meridian-payments"
    managed_by = "terraform"
  }

  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "third_party_api_token" {
  secret                 = google_secret_manager_secret.third_party_api_token.id
  secret_data_wo         = "mrd_tok_${random_password.third_party_api_token.result}"
  secret_data_wo_version = 1
}

# Least-privilege secret-level IAM: Cloud Run SA can read ONLY these two secrets.
resource "google_secret_manager_secret_iam_member" "api_db_password_accessor" {
  secret_id = google_secret_manager_secret.db_password.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.api.email}"
}

resource "google_secret_manager_secret_iam_member" "api_token_accessor" {
  secret_id = google_secret_manager_secret.third_party_api_token.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.api.email}"
}
