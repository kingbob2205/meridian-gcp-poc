# Custom EU-only VPC replacing the default VPC rejected in CLARIFICATIONS.md.
resource "google_compute_network" "main" {
  name                    = "meridian-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"

  depends_on = [google_project_service.apis]
}

# Subnet for Cloud Run Direct VPC Egress (EU-only).
resource "google_compute_subnetwork" "app" {
  name                     = "meridian-subnet-app"
  ip_cidr_range            = "10.10.0.0/24"
  region                   = var.region
  network                  = google_compute_network.main.id
  private_ip_google_access = true
}

# Dedicated subnet for the Cloud SQL Private Service Connect (PSC) endpoint.
resource "google_compute_subnetwork" "psc" {
  name                     = "meridian-subnet-psc"
  ip_cidr_range            = "10.10.1.0/24"
  region                   = var.region
  network                  = google_compute_network.main.id
  private_ip_google_access = true
}

# Single internal IP allocated for the Cloud SQL PSC endpoint (no VPC peering / CIDR exhaustion).
resource "google_compute_address" "sql_psc_ip" {
  name         = "meridian-sql-psc-ip"
  region       = var.region
  address_type = "INTERNAL"
  purpose      = "GCE_ENDPOINT"
  subnetwork   = google_compute_subnetwork.psc.id
}

resource "google_compute_forwarding_rule" "sql_psc_endpoint" {
  name                    = "meridian-sql-psc-endpoint"
  region                  = var.region
  network                 = google_compute_network.main.id
  ip_address              = google_compute_address.sql_psc_ip.id
  target                  = google_sql_database_instance.postgres.psc_service_attachment_link
  load_balancing_scheme   = ""
  allow_psc_global_access = false
}

# Explicit least-privilege firewall rules (unlike default VPC's open SSH/RDP/ICMP/internal rules).
resource "google_compute_firewall" "allow_egress_sql_psc" {
  name               = "meridian-allow-egress-sql-psc"
  network            = google_compute_network.main.name
  direction          = "EGRESS"
  priority           = 1000
  destination_ranges = ["${google_compute_address.sql_psc_ip.address}/32"]

  allow {
    protocol = "tcp"
    ports    = ["5432"]
  }
}

resource "google_compute_firewall" "deny_egress_other_private" {
  name               = "meridian-deny-egress-other-private"
  network            = google_compute_network.main.name
  direction          = "EGRESS"
  priority           = 65000
  destination_ranges = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]

  deny {
    protocol = "all"
  }
}

resource "google_compute_firewall" "deny_all_ingress" {
  name          = "meridian-deny-all-ingress"
  network       = google_compute_network.main.name
  direction     = "INGRESS"
  priority      = 65534
  source_ranges = ["0.0.0.0/0"]

  deny {
    protocol = "all"
  }
}
