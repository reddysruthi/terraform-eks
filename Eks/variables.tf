############ network ##############
variable "region" {
  type    = string
  default = ""
}
variable "map_tag" {
  type = map(string)
  default = {
    "map-migrated" = "MPE39939"
  }
}
variable "allowed_zones" {
  type    = list(string)
  default = null
}
variable "create_network" {
  type    = bool
  default = false
}
variable "vpc_cidr_block" {
    type = string
    default = "10.96.8.0/21"
}
variable "subnet_pub_cidr_block" {
  type    = list(string)
}
variable "create_network_routes" {
  type    = bool
  default = true
}
variable "subnet_priv_cidr_block" {
  type    = list(string)
}

############ security ########
variable "test_internal_networking" {
  type = bool
  default = false
}
variable "create_security_group" {
    type = bool
    default = false
}


################### EKS ############################
variable "eks_ami_id" {
  type    = string
  default = null
}
variable "test_node_pool_count" {
  type    = number
  default = 0
}
variable "test_node_pool_max_count" {
  type    = number
  default = 0
}
variable "eks_version" {
  type    = string
  default = null
}
variable "eks_enabled_cluster_log_types" {
  description = "Array of types of values to be logged to CloudWatch Logs. For possible values, visit https://docs.aws.amazon.com/eks/latest/userguide/control-plane-logs.html"
  type        = list(string)
  default     = []
}
variable "eks_endpoint_public_access" {
  type    = bool
  default = true
}
variable "eks_endpoint_public_access_cidr_blocks" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}
variable "eks_endpoint_private_access" {
  type    = bool
  default = true
}
variable "eks_envelope_encryption" {
  type    = bool
  default = false
}
variable "eks_envelope_kms_key_arn" {
  type    = string
  default = null
}
variable "eks_node_group_ami_release_version" {
  type    = string
  default = null
}
variable "test_node_pool_disk_size" {
  type    = string
  default = "100"
}
variable "default_disk_type" {
  type    = string
  default = "gp3"
}
variable "tag_specifications" {
  description = "The tags to apply to the resources during launch"
  type        = list(string)
  default     = ["instance", "volume", "network-interface"]
}
variable "test_node_pool_min_count" {
  type    = number
  default = 0
}
variable "test_node_pool_desired_count" {
  type    = number
  default = 0
}
variable "test_node_pool_instance_type" {
  type    = string
  default = ""
}
variable "default_iam_identifier_path" {
  type    = string
  default = null
}
variable "default_iam_permissions_boundary_arn" {
  type    = string
  default = null
}
variable "eks_kube_proxy_version" {
  type    = string
  default = null
}
variable "eks_coredns_version" {
  type    = string
  default = null
}
variable "default_kms_key_arn" {
  type    = string
  default = null
}
variable "ekscluster_name" {
    type = string
    default = null
}
variable "eks_vpc_cni_version" {
  type    = string
  default = null
}
