provider "google" {
  project     = var.project_id
  region      = "us-central1"
  credentials = file("account.json")
}

resource "google_container_cluster" "primary" {
  name     = "wiz-cluster"
  location = "us-central1-a"
}

resource "google_compute_instance" "mongo-db" {
  name         = "mongo-db"
  machine_type = "e2-medium"
  zone         = "us-central1-a"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-9"
    }
  }

  network_interface {
    network = "default"
    access_config {}
  }
}

resource "google_storage_bucket" "mongo-backups" {
  name          = "mongo-backup-bucket"
  location      = "US"
  uniform_bucket_level_access = true
}
