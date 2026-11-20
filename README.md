# Meridian Payments — Google Cloud Architecture POC

- **Live Health Endpoint:** `https://meridian-api-kwrpwuypia-ey.a.run.app/health` (deployed commit: `85f7d25`)
- **GCP Project (`roles/viewer` granted to `group:gcp-hr@comm-it.cloud`):** `meridian-gcp-poc-ho26` (`europe-west3`)
- **Supporting Docs:** [`CLARIFICATIONS.md`](./CLARIFICATIONS.md) (Commit #1, unmodified) · [`ASSUMPTIONS.md`](./ASSUMPTIONS.md) · [`AI-LOG.md`](./AI-LOG.md)

## Architecture & Key Decisions
- **Compute Choice (`Cloud Run v2` + `Direct VPC Egress`):** Chosen over `GKE` and `Compute Engine` for a single stateless HTTP API to eliminate node/control-plane overhead, scale to zero (`~$16–$20/mo` total POC cost), avoid paid Serverless VPC Access Connector VMs, and preserve container portability if Meridian later adopts GKE. Runs a static **Go 1.26 (`net/http`)** binary in `gcr.io/distroless/static-debian12:nonroot`.
- **Network & Database (`Custom VPC` + `Private Service Connect`):** Rejected the brief's `default` VPC in favor of EU-only `meridian-vpc` (`10.10.0.0/24` app, `10.10.1.0/24` PSC) with explicit deny-all ingress and tagged egress (`target_tags = ["meridian-api"]`) to the PSC IP (`10.10.1.2:5432`) only. Cloud SQL PostgreSQL 16 (`ENTERPRISE`, `db-f1-micro`, PITR enabled) has **zero public IP** (`ipv4_enabled = false`), `ssl_mode = "ENCRYPTED_ONLY"`, and `psc_enabled = true`.
- **Secrets & Runtime Verification:** Both `meridian-db-password` and `meridian-third-party-api-token` use EU-only `user_managed` replication (`europe-west3`), write-only `secret_data_wo` Terraform versions, and per-secret `secretAccessor` IAM for `meridian-api-sa`. Every `GET /health` request reads Secret Manager live via ADC and runs `SELECT 1` over TLS 1.2+ (verified live: disabling the token version flips `/health` to HTTP `503` + `"secret":"error"` immediately).
- **Bonus Keyless CI/CD (`.github/workflows/terraform-plan.yml`):** Refused static SA JSON keys; implemented **Workload Identity Federation (`WIF`)** locked to `kingbob2205/meridian-gcp-poc` `pull_request` events using read-only `meridian-tf-plan-sa` (`roles/storage.objectUser` on the state bucket). Verified green live on [PR #1](https://github.com/kingbob2205/meridian-gcp-poc/pull/1).

## How to Run
```bash
./scripts/bootstrap.sh meridian-gcp-poc-ho26 <BILLING_ACCOUNT_ID> europe-west3
cd infra && terraform init
terraform apply -target=google_project_service.apis -target=google_artifact_registry_repository.api \
  -var="image_uri=europe-west3-docker.pkg.dev/meridian-gcp-poc-ho26/meridian-api/api:init" -var="git_sha=init"
gcloud builds submit ../app --project=meridian-gcp-poc-ho26 --region=europe-west3 --config=../app/cloudbuild.yaml \
  --substitutions=_GIT_SHA=$(git rev-parse --short HEAD),_IMAGE_URI=europe-west3-docker.pkg.dev/meridian-gcp-poc-ho26/meridian-api/api:$(git rev-parse --short HEAD)
terraform apply -var="image_uri=europe-west3-docker.pkg.dev/meridian-gcp-poc-ho26/meridian-api/api:$(git rev-parse --short HEAD)" \
  -var="git_sha=$(git rev-parse --short HEAD)"
```

## Working With AI (`AI-LOG.md`)
- **Tools & Share:** `Antigravity` IDE (`Gemini 4 Neon (High)` + an independent fresh-context audit subagent). AI generated ~85% of the Go/HCL/workflow boilerplate; 100% of architectural pushback, security trade-offs, and live troubleshooting decisions were directed and reviewed by me.
- **Three Places Where I Rejected or Corrected the AI (with `AI-LOG.md` pointers):**
  1. **Go + Distroless over Python/FastAPI (`AI-LOG.md`, Turns 14–17):** Rejected the AI's initial Python/FastAPI plan in favor of a minimal static Go binary on `distroless:nonroot` for faster Cloud Run cold starts and a smaller payments container attack surface.
  2. **WIF Least-Privilege Hardening (`AI-LOG.md`, Turns 18–19):** Rejected the AI's initial `roles/storage.objectAdmin` state-bucket grant and repo-wide OIDC condition in `infra/iam_wif.tf`, tightening to `roles/storage.objectUser` and `assertion.event_name == 'pull_request'`.
  3. **POC Cost Discipline & Write-Only Secrets (`AI-LOG.md`, Turns 18–19 & Turns 25–26):** Rejected adding always-on VPC Flow Logs/Firewall Logging to the 3-week POC to keep spend minimal (deferring to prod cutover), and directed migrating Secret Manager versions to write-only `secret_data_wo` to remove secret payloads from version state and eliminate `secretmanager.versions.access` from read-only CI plans.

## Time Spent & What I Would Do Differently With More Time
- **Actual Time Spent:** ~1 hour 5 minutes (well within the 5-hour hard stop).
- **Production Hardening Next Steps:** Org Policies (`compute.skipDefaultNetworkCreation`, `iam.disableServiceAccountKeyCreation`, `gcp.resourceLocations`), Cloud SQL `REGIONAL` HA + `deletion_protection = true` + `CMEK` (Cloud KMS), External Application LB + `Cloud Armor` WAF + mTLS/OIDC (`ingress = INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER`), VPC Flow Logs + Firewall Logging (`PCI-DSS Req. 10`), `VPC-SC`, CI-triggered `Cloud Run Job` schema migrations, pinned `go.sum`, and Binary Authorization.
