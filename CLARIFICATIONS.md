# Clarifications Email — Meridian Payments (Day 1)

**To:** Platform Lead, Meridian Payments  
**From:** Hazav Ogdan, Google Cloud Architect, Commit  
**Subject:** Meridian Payments GCP Evaluation — Architectural Pushback & Key Clarifications Before Kickoff

Hi,

Thanks for sharing the brief for the three-week Google Cloud evaluation. I am ready to stand up the production-shaped API and PostgreSQL slice so your team can test it hands-on.

Before I provision anything, there are **three design patterns in the brief that I recommend we do not build as requested**—particularly given Meridian's EU payments compliance posture—along with **four quick clarifications** so the evaluation accurately reflects your production target.

### 1. Three Patterns I Recommend Changing

1. **Do not use the `default` VPC (even for the POC):**  
   The `default` VPC creates auto-mode subnets in every GCP region worldwide (including US and APAC, which conflicts with EU data residency controls and creates CIDR collision risks when peering with your AWS estate or expanding to the US later) and ships with overly permissive firewall rules (`default-allow-internal`, `ssh`, `rdp`, `icmp`) that will fail an external payments audit. Furthermore, Cloud SQL private connectivity does not require sharing the default VPC: I recommend an EU-only **custom VPC** with explicit least-privilege firewall rules and **Private Service Connect (`PSC`)** to expose Cloud SQL over a single internal IP without VPC peering limitations.

2. **Do not store a static Service Account JSON key in GitHub Secrets:**  
   Long-lived JSON keys cannot be auto-rotated cleanly, carry a high blast radius if leaked, and are a standard PCI-DSS / SOC2 audit finding. I strongly advise refusing this pattern even if it exists elsewhere in your estate. Instead, we should authenticate GitHub Actions via **Workload Identity Federation (`WIF`)** using short-lived OIDC tokens scoped strictly to your repository and branch. I also recommend splitting the pipeline so pull requests run `terraform plan` with a read-only identity, while `terraform apply` runs only after peer approval on `main`.

3. **Private-only database vs. schema migrations from developer laptops:**  
   Keeping PostgreSQL completely unreachable from the internet while letting developers run migrations directly from their laptops is a direct contradiction if solved with public endpoints or IP allowlisting. For a payments database, the clean production pattern is running peer-reviewed migrations inside the VPC via a CI/CD-triggered **Cloud Run Job** (or Cloud Build private pool), removing laptop database access altogether. If interactive break-glass access is genuinely required for debugging, we should route it through **Identity-Aware Proxy (`IAP`) TCP tunneling** to an ephemeral, no-public-IP bastion with **Cloud SQL Auth Proxy**, MFA, and full Cloud Audit Logs—never direct laptop connectivity.

### 2. Four Quick Clarifications

1. **Compliance & future US expansion:** Which compliance regimes are in scope for this service (`PCI-DSS` CDE, `GDPR`, `DORA`, local Lithuanian/German financial requirements)? When you expand to US customers later, should I assume strict regional isolation (a separate US stack and database) rather than cross-replicating EU customer data out of the EU?
2. **Region, HA & RPO/RTO targets:** With headquarters in Vilnius and customers in Lithuania and Germany, `europe-west3` (Frankfurt) is my default recommendation for latency, EU data residency, and full GCP service parity. What are your production `RPO`/`RTO` and HA targets (e.g., Regional HA, Point-in-Time Recovery, and customer-managed KMS keys) versus acceptable cost-saving compromises for the three-week evaluation?
3. **API edge security & runtime parity:** Beyond exposing a health endpoint for this evaluation, how will callers reach the API in production (External Application Load Balancer + `Cloud Armor` WAF + mTLS/OIDC, or internal-only)? Also, is there a strong operational reason to mirror Kubernetes (`GKE`) from AWS, or is serverless (`Cloud Run`) acceptable to minimize operational overhead for stateless HTTP services?
4. **AWS dependencies & POC guardrails:** Does the evaluation API need live connectivity back to AWS (e.g., via HA VPN) or to a specific external third-party endpoint, and do you have a monthly spend cap for the three-week POC?

If you are busy and I do not hear back before we kick off tomorrow, I will proceed with the hardened defaults above—an EU-only custom VPC in `europe-west3`, private Cloud SQL over PSC, `Cloud Run` with Direct VPC Egress, `Secret Manager` with per-secret least-privilege IAM, `WIF` for CI/CD, and a documented CI-driven migration pattern—and log every assumption clearly so we stay on schedule.

Happy to jump on a quick 15-minute call if easier.

Best regards,  
**Hazav Ogdan**  
Google Cloud Architect, Commit
