terraform {
  backend "gcs" {
    bucket = "meridian-gcp-poc-ho26-tfstate"
    prefix = "meridian-poc/state"
  }
}
