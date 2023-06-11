provider "google" {
  project = var.host_project_id
}

resource "google_project_service" "run" {
  service = "run.googleapis.com"
}

resource "google_cloud_run_service" "nats-client-flutter" {
  name     = "nats-client-flutter"
  location = var.region

  template {
    spec {
      containers {
        image = "gcr.io/${var.host_project_id}/nats-flutter-web"
        ports {
          container_port = 80
        }
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  depends_on = [google_project_service.run]
}

resource "google_cloud_run_service_iam_member" "allUsers" {
  service  = google_cloud_run_service.nats-client-flutter.name
  location = google_cloud_run_service.nats-client-flutter.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

output "url" {
  value = google_cloud_run_service.nats-client-flutter.status[0].url
}