# Architectural Assumptions & Decisions (`ASSUMPTIONS.md`)

This document records the concrete decision taken for every objection and open question raised in [`CLARIFICATIONS.md`](./CLARIFICATIONS.md) under the assumption that no reply arrived before implementation began, plus additional engineering assumptions made during the build.

---

## 1. Resolution of Pushback Items from `CLARIFICATIONS.md`

### 1.1 Default VPC Pushback -> Custom EU-Only VPC + Private Service Connect (`PSC`)
- **Customer request:** Put everything in the `default` VPC to keep Cloud SQL private IP simple.
- **Decision taken:** **Rejected `default` VPC.** Provisioned a dedicated custom-mode VPC (`meridian-vpc`, `auto_create_subnetworks = false`) with two EU-only subnets in `europe-west3` (`subnet-app` `10.10.0.0/24` and `subnet-psc` `10.10.1.0/24`), explicit least-privilege firewall rules (allowing only TCP `5432` from `subnet-app` to the PSC IP and denying all ingress), and **Private Service Connect (`PSC`)** for Cloud SQL.
- **Reasoning:** Default VPC ships with permissive ingress rules (`ssh`, `rdp`, `icmp`, internal-all) and auto-creates subnets across non-EU regions (including US/APAC), violating financial audit principles and risking CIDR overlap with Meridian's AWS estate or future US deployment. Using PSC also disproves the premise that Cloud SQL private IP requires VPC peering or sharing the default VPC, avoiding peering transitivity limits and IP range exhaustion.

### 1.2 Static SA JSON Key Pushback -> Workload Identity Federation (`WIF`)
- **Customer request:** Store a Service Account JSON key in GitHub Secrets so GitHub Actions can run `terraform apply`.
- **Decision taken:** **Refused static JSON keys.** Provisioned a GCP Workload Identity Pool & OIDC Provider scoped strictly via `attribute_condition` to `kingbob2205/meridian-gcp-poc`, paired with a read-only planning Service Account (`meridian-tf-plan-sa`) and a GitHub Actions pull-request workflow running `terraform fmt`, `terraform validate`, and `terraform plan`.
- **Reasoning:** Static SA JSON keys are long-lived credentials with high blast radius and fail PCI-DSS / SOC2 audits. Short-lived OIDC tokens via WIF eliminate static secret rotation altogether. Splitting `plan` (read-only SA on PR) from `apply` (gated behind human review on `main` in production) enforces separation of duties.

### 1.3 Private DB vs. Developer Laptop Migrations -> CI/CD Cloud Run Job Pattern (No Public IP, No Idle Bastion)
- **Customer request:** Database must never be reachable from the internet, yet developers must run schema migrations from laptops.
- **Decision taken:** Kept Cloud SQL **100% private** (`ipv4_enabled = false`, zero public IP) and **did not deploy** an always-on bastion VM in this POC. Documented the production target as **CI/CD-driven migrations via a VPC-attached Cloud Run Job** (`Flyway`/`Liquibase`/`goose` executing peer-reviewed SQL from Git), with **IAP TCP tunneling -> ephemeral private bastion -> Cloud SQL Auth Proxy** reserved strictly for audited break-glass troubleshooting.
- **Reasoning:** Exposing Postgres over public IP (even with allowlists) directly violates the auditor constraint. Deploying an always-on bastion in a 3-week POC adds unnecessary cost and attack surface when CI-driven migrations are the standard payments pattern.

---

## 2. Resolution of Clarifying Questions from `CLARIFICATIONS.md`

### 2.1 Compliance & Future US Expansion
- **Decision taken:** Treated the workload as EU-regulated (`PCI-DSS` CDE / `GDPR` / `DORA` posture). Locked all POC resources (Cloud Run, Cloud SQL, PSC subnets, Artifact Registry, GCS Terraform state bucket, and Secret Manager `user_managed` replication) strictly to **`europe-west3` (Frankfurt, Germany)**.
- **Reasoning:** Frankfurt provides low latency to both Germany and Vilnius, full GCP service parity, and strict EU data residency. Future US customers must be served from an **isolated US regional deployment** (separate project/VPC/Cloud SQL in `us-east4` or `us-central1`) rather than cross-replicating EU PII out of the EU.

### 2.2 Region, Availability & RPO/RTO Targets (POC vs. Production Delta)
- **Decision taken:** Deployed in `europe-west3` using `db-f1-micro` (`ZONAL`), `ssl_mode = "ENCRYPTED_ONLY"`, automated daily backups enabled, `deletion_protection = false` (so teardown after review is clean), and Google-managed encryption.
- **Reasoning:** Balances realistic production shape against a 3-week evaluation budget (~$16–$20/month). For production cutover, upgrade to `REGIONAL` High Availability, Point-in-Time Recovery (`PITR`), `deletion_protection = true`, custom vCPU/RAM sizing, and Customer-Managed Encryption Keys (`CMEK` via Cloud KMS).

### 2.3 API Edge Security & Compute Runtime Choice
- **Decision taken:** Selected **Cloud Run v2** with **Direct VPC Egress** running a minimal **Go (`net/http`) distroless container** (over Python/FastAPI for minimal image size, zero OS shell/package manager attack surface, and sub-second cold starts). Exposed `GET /health` publicly via `roles/run.invoker` (`allUsers`) solely to satisfy the evaluation contract.
- **Reasoning:** Cloud Run eliminates Kubernetes control-plane/node overhead for a single stateless HTTP API while keeping full container portability if Meridian later adopts GKE. In production, place Cloud Run behind an External Application Load Balancer + **Cloud Armor WAF** (`ingress = INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER`) with mTLS/OIDC client authentication.

### 2.4 AWS Dependencies & POC Guardrails
- **Decision taken:** Assumed zero live AWS VPN/Interconnect dependency during the 3-week slice, represented the third-party provider API token as a real Secret Manager secret verified live on every request, and targeted **<$25/month** total POC spend inside a dedicated isolated GCP project.
- **Reasoning:** Avoids provisioning unused HA VPN gateways (~$75+/month) before Meridian commits to migration, while isolating reviewer read-only access (`gcp-hr@comm-it.cloud`) to a clean project.

---

## 3. Additional Engineering Assumptions

| Area | Decision for POC | Production Upgrade Path |
| :--- | :--- | :--- |
| **Secret Provisioning** | Terraform generates `random_password` values into Secret Manager versions so `terraform apply` is 100% reproducible with zero console steps. | Create empty secret shells in Terraform and inject secret versions out-of-band (Vault / KMS / CI secret-sync) or use **IAM Database Authentication** so database passwords never enter Terraform state. |
| **Live `/health` Verification** | Calls **Secret Manager API live** on each request (under `meridian-api-sa`) and executes `SELECT 1` over TLS (`sslmode=require`) against the Cloud SQL PSC IP. | Cache short-lived secrets in memory with TTL + pool DB connections (`pgxpool`) to avoid per-request Secret Manager API quota/latency overhead under high RPS. |
| **VPC Egress Mode** | `PRIVATE_RANGES_ONLY` so RFC1918 DB traffic traverses the Custom VPC to PSC while Google API traffic reaches Secret Manager without requiring a paid Cloud NAT gateway. | Evaluate `ALL_TRAFFIC` + **Private Google Access** (`private.googleapis.com` / `restricted.googleapis.com`) + **Cloud NAT** + **VPC Service Controls (`VPC-SC`)** for strict PCI-DSS egress auditing. |
| **Remote State Bootstrap** | One-time `scripts/bootstrap.sh` creates the isolated project, links billing, and provisions the versioned, uniform-access GCS state bucket (`europe-west3`). | Managed via an Organization-level Terraform Project Factory (e.g., Google `Cloud Foundation Fabric` FAST) under Org Folders (`Prod`, `Non-Prod`, `Shared`) with `Org Policies` enforcing `me-west1`/`europe-west3` residency and disabling SA key creation globally. |
