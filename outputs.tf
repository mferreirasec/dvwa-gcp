output "external_ip" {
  description = "External IP of the DVWA Load Balancer"
  value       = google_compute_global_address.dvwa_ip.address
}

output "logging_metric_name" {
  description = "Name of the logging metric for HTTP traffic"
  value       = google_logging_metric.dvwa_http_traffic.name
}
