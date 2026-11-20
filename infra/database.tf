resource "random_id" "sql_suffix" {
  byte_length = 3
}

resource "random_password" "db_password" {
  length  = 32
  special = false
}

resource "google_sql_database_instance" "postgres" {
  name                = "meridian-pg-${random_id.sql_suffix.hex}"
  database_version    = "POSTGRES_16"
  region              = var.region
  deletion_protection = false # Set true in production; false here for post-review teardown.

  settings {
    edition           = "ENTERPRISE"
    tier              = "db-f1-micro" # Upgrade to custom vCPU/RAM + REGIONAL HA in production.
    availability_type = "ZONAL"
    disk_autoresize   = true
    disk_size         = 10
    disk_type         = "PD_SSD"

    ip_configuration {
      ipv4_enabled = false
      ssl_mode     = "ENCRYPTED_ONLY"

      psc_config {
        psc_enabled               = true
        allowed_consumer_projects = [var.project_id]
      }
    }

    backup_configuration {
      enabled                        = true
      start_time                     = "02:00"
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7
    }

    insights_config {
      query_insights_enabled = true
    }

    user_labels = {
      env        = "poc"
      workload   = "meridian-payments"
      managed_by = "terraform"
    }
  }

  depends_on = [google_project_service.apis]
}

resource "google_sql_database" "meridian" {
  name     = "meridian"
  instance = google_sql_database_instance.postgres.name
}

resource "google_sql_user" "app" {
  name     = "meridian_app"
  instance = google_sql_database_instance.postgres.name
  password = random_password.db_password.result
}
