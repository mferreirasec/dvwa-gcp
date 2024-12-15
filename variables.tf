
variable "project_id" {
  description = "GCP Project ID"
  type        = string
  default     = "PROJECT_ID"
}

variable "region" {
  description = "GCP region for resources"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone for the compute instance"
  type        = string
  default     = "us-central1-a"
}

variable "domain_name" {
  description = "Domain for the HTTPS setup"
  type        = string
  default     = "www.domain.com"
}

variable "source_ip_ranges" {
  description = "List of IPs to block (e.g., suspicious IPs)"
  type        = list(string)
  default     = ["1.2.3.4"]
}
