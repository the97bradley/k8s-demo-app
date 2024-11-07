variable "MONGO_USERNAME" {}
variable "MONGO_PASSWORD" {}

provider "google" {
  project     = var.project_id
  region      = "us-central1"
  credentials = var.gcp_credentials
}

terraform {
  backend "gcs" {
    bucket = "k8s-proj-state-file"
  }
}



resource "google_cloudfunctions_function" "mongo_backup_function" {
  name        = "mongo_backup_function"
  runtime     = "python39"
  entry_point = "backup"
  trigger_http = true
  source_archive_bucket =  "backup-function-code"
  source_archive_object =  "backup-func.zip"

}

resource "google_compute_address" "mongo_static_ip" {
  name   = "mongo-static-ip"
  region = "us-central1"
}


resource "google_compute_instance" "mongo_instance" {
  name         = "mongo-instance"
  machine_type = "e2-medium"
  zone         = "us-central1-a"

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-1604-xenial-v20200807"
    }
  }

  network_interface {
    network = "default"
    access_config {
      nat_ip = google_compute_address.mongo_static_ip.address
    }
  }


  service_account {
    email  = "mongo-vm-account@k8s-proj-439420.iam.gserviceaccount.com"
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  tags = ["mongo-firewall"]


  metadata_startup_script = <<-EOF
    #!/bin/bash
    sudo apt-get update
    wget -qO - https://www.mongodb.org/static/pgp/server-4.0.asc | sudo apt-key add -
    echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu $(lsb_release -cs)/mongodb-org/4.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-4.0.list
    sudo apt-get update
    sudo apt-get install -y mongodb-org=4.0.24 mongodb-org-server=4.0.24 mongodb-org-shell=4.0.24 mongodb-org-mongos=4.0.24 mongodb-org-tools=4.0.24 --allow-unauthenticated -y


    # Enable MongoDB authentication
    echo "security:
      authorization: disabled" | sudo tee -a /etc/mongod.conf

    ##Allow external connection to the db
    sudo sed -i 's/bindIp: 127.0.0.1/bindIp: 0.0.0.0/' /etc/mongod.conf
  

    # Start MongoDB
    sudo systemctl enable mongod
    sudo systemctl start mongod

    # Wait for MongoDB to start
    sleep 10
    echo "hello"

    # Add an admin user with credentials from environment variables
    mongo <<MONGO_EOF
    use admin
    db.createUser({
      user: "${var.MONGO_USERNAME}",
      pwd: "${var.MONGO_PASSWORD}",
      roles: [{ role: "root", db: "admin" }]
    })
    MONGO_EOF
  EOF
}


resource "google_compute_firewall" "allow_all_ports" {
  name    = "allow-all-ports"
  network = "default"
  project = "k8s-proj-439420"

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  target_tags = ["mongo-firewall"]

  source_ranges = ["0.0.0.0"] 
}


# Output MongoDB instance IP for dynamic URI construction
output "mongo_ip" {
  value = google_compute_instance.mongo_instance.network_interface[0].access_config[0].nat_ip
}



# Cloud Scheduler Job to Trigger Cloud Function
resource "google_cloud_scheduler_job" "mongo_backup_scheduler" {
  name        = "mongo_backup_scheduler"
  description = "Triggers MongoDB backup function hourly"
  schedule    = "0 * * * *"  # Every hour
  time_zone   = "America/Los_Angeles"

  http_target {
    uri          = google_cloudfunctions_function.mongo_backup_function.https_trigger_url
    http_method  = "GET"
    oidc_token {
      service_account_email = google_cloudfunctions_function.mongo_backup_function.service_account_email
    }
  }
}

resource "google_compute_firewall" "allow_all_ports" {
  name    = "allow-all-ports"
  network = "default"
  project = "k8s-proj-439420"

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  target_tags = ["mongo-firewall"]

  source_ranges = ["0.0.0.0"] 
}



# Kubernetes Cluster
resource "google_container_cluster" "primary" {
  name     = "host-cluster"
  location = "us-central1-a"
  deletion_protection = "false"




  initial_node_count = 2




  node_config {
    machine_type = "e2-medium"
  }

}

