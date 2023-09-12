data "aws_partition" "current" {}

locals {
  aws_partition  = data.aws_partition.current.partition
  eks_custom_ami = var.eks_ami_id != null
  eks_ami_type   = local.eks_custom_ami ? "CUSTOM" : "AL2_x86_64"
  total_node_pool_count = var.test_node_pool_count + var.test_node_pool_max_count

  test_node_pool_autoscaling = var.test_node_pool_max_count > 0
  eks_cluster_subnet_ids      = aws_subnet.test_vpc_sn_priv[*].id
  eks_backend_node_subnet_ids = aws_subnet.test_vpc_sn_priv[*].id
}

# Cluster
resource "aws_eks_cluster" "test_cluster" {
  count = min(local.total_node_pool_count, 1)

  name                      = var.ekscluster_name
  version                   = var.eks_version
  role_arn                  = aws_iam_role.test_eks_role[0].arn
  enabled_cluster_log_types = var.eks_enabled_cluster_log_types

  vpc_config {
    endpoint_public_access = var.eks_endpoint_public_access
    public_access_cidrs    = var.eks_endpoint_public_access_cidr_blocks

    endpoint_private_access = var.eks_endpoint_private_access
    subnet_ids              = local.eks_cluster_subnet_ids

    security_group_ids = [
      aws_security_group.test_internal_networking[0].id,
    ]
  }
  dynamic "encryption_config" {
    for_each = range(var.eks_envelope_encryption ? 1 : 0)

    content {
      provider {
        key_arn = var.eks_envelope_kms_key_arn != null ? var.eks_envelope_kms_key_arn : coalesce(var.default_kms_key_arn, try(aws_kms_key.test_cluster_key[0].arn, null))
      }
      resources = ["secrets"]
    }

  }

  tags = merge(var.map_tag,{
    Name = "test-cluster"
  })


  depends_on = [
    aws_iam_role_policy_attachment.amazon_eks_cluster_policy,
    aws_iam_role_policy_attachment.amazon_eks_vpc_resource_controller,
  ]
   lifecycle{
      create_before_destroy = true
    }
}

# kms key for a cluster

resource "aws_kms_key" "test_cluster_key" {
  count = var.eks_envelope_encryption && local.total_node_pool_count > 0 && var.eks_envelope_kms_key_arn == null && var.default_kms_key_arn == null ? 1 : 0

  description         = "test-cluster-key"
  enable_key_rotation = true
  tags = merge(var.map_tag,{
    Name = "test-kms-key"
  })
}

# Node Pools
## Default EKS AL2 Release Version
data "aws_ssm_parameter" "eks_ami_release_version" {
  count = var.eks_node_group_ami_release_version == "latest" ? min(local.total_node_pool_count, 1) : 0

  name = "/aws/service/eks/optimized-ami/${aws_eks_cluster.test_cluster[0].version}/amazon-linux-2/recommended/release_version"
  #amazon-linux-2-arm64
}

## Custom Launch Template
resource "aws_launch_template" "test_demo" {
  count    = local.eks_custom_ami ? min(var.test_node_pool_count + var.test_node_pool_max_count, 1) : 0
  image_id = var.eks_ami_id

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.test_node_pool_disk_size
      volume_type           = var.default_disk_type
      encrypted             = true
      delete_on_termination = true
    }
  }
   user_data = base64encode(templatefile("${path.module}/templates/userdata.sh.tpl", {
     cluster_name = aws_eks_cluster.test_cluster[0].name 
     bootstrap_extra_args = "--use-max-pods false --kubelet-extra-args '--max-pods=110'"
     cluster_auth_base64 = aws_eks_cluster.test_cluster[0].certificate_authority.0.data
     cluster_endpoint = aws_eks_cluster.test_cluster[0].endpoint
    }))
  tags = merge(var.map_tag,{
   Name = "test-template"
  })
  dynamic "tag_specifications" {
    for_each = toset(var.tag_specifications)

    content {
      resource_type = tag_specifications.key
      tags  = merge(var.map_tag, { 
        Name = "test-node" })
    }
  }

  depends_on = [ aws_eks_cluster.test_cluster ]
}

resource "aws_eks_node_group" "test_pool" {
  count = min(var.test_node_pool_count + var.test_node_pool_max_count, 1)

  cluster_name = aws_eks_cluster.test_cluster[0].name

  ami_type        = local.eks_ami_type
  release_version = local.eks_custom_ami ? null : (var.eks_node_group_ami_release_version == "latest" ? nonsensitive(data.aws_ssm_parameter.eks_ami_release_version[0].value) : var.eks_node_group_ami_release_version)

  dynamic "launch_template" {
    for_each = range(local.eks_custom_ami ? 1 : 0)

    content {
      id      = aws_launch_template.test_demo[0].id
      version = aws_launch_template.test_demo[0].latest_version
    }
  }
   # Create a unique name to allow nodepool replacements
  node_group_name_prefix = "test_pool"
  node_role_arn          = aws_iam_role.test_eks_node_role[0].arn
  subnet_ids             = local.eks_backend_node_subnet_ids
  instance_types         = [var.test_node_pool_instance_type]
  disk_size              = local.eks_custom_ami ? null : var.test_node_pool_disk_size

  scaling_config {
    desired_size = var.test_node_pool_desired_count
    min_size     = var.test_node_pool_min_count 
    max_size     = var.test_node_pool_max_count 
  }

  labels = {
    workload = "test-demo"
  }
  tags = merge({
    
    test_node_type   = "test-pool"

    "k8s.io/cluster-autoscaler/${aws_eks_cluster.test_cluster[0].name}" = "owned"
    "k8s.io/cluster-autoscaler/enabled"                                   = "TRUE"
  })

  depends_on = [
    aws_iam_role_policy_attachment.amazon_eks_worker_node_policy,
    aws_iam_role_policy_attachment.amazon_ec2_container_registry_read_only,
    aws_iam_role.test_addon_vpc_cni_role,
    # Don't create the node-pools until kube-proxy and vpc_cni plugins are created
    aws_eks_addon.kube_proxy,
    aws_eks_addon.vpc_cni,
  ]
}

# Roles

resource "aws_iam_role" "test_eks_role" {
  count = min(local.total_node_pool_count, 1)
  name  = "test-eks-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      },
    ]
  })

  path                 = var.default_iam_identifier_path
  permissions_boundary = var.default_iam_permissions_boundary_arn
  tags = {
  Name = "test-eks-role"
  }
}

resource "aws_iam_role" "test_eks_node_role" {
  count = min(local.total_node_pool_count, 1)
  name  = "test-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })

  path                 = var.default_iam_identifier_path
  permissions_boundary = var.default_iam_permissions_boundary_arn
  tags = {
    Name = "test-eks-node-role"
  }
}

# Policies

resource "aws_iam_role_policy_attachment" "amazon_eks_cluster_policy" {
  count      = min(local.total_node_pool_count, 1)
  policy_arn = "arn:${local.aws_partition}:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.test_eks_role[0].name
}

resource "aws_iam_role_policy_attachment" "amazon_eks_vpc_resource_controller" {
  count      = min(local.total_node_pool_count, 1)
  policy_arn = "arn:${local.aws_partition}:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.test_eks_role[0].name 
}

resource "aws_iam_role_policy_attachment" "amazon_eks_worker_node_policy" {
  count      = min(local.total_node_pool_count, 1)
  policy_arn = "arn:${local.aws_partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.test_eks_node_role[0].name
}
resource "aws_iam_role_policy_attachment" "AmazonSSMManagedInstanceCore" {
  count      = min(local.total_node_pool_count, 1)
  policy_arn = "arn:${local.aws_partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.test_eks_node_role[0].name
}

resource "aws_iam_role_policy_attachment" "amazon_ec2_container_registry_read_only" {
  count      = min(local.total_node_pool_count, 1)
  policy_arn = "arn:${local.aws_partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.test_eks_node_role[0].name
}

# Addons

## kube_proxy
resource "aws_eks_addon" "kube_proxy" {
  count = min(local.total_node_pool_count, 1)

  cluster_name      = aws_eks_cluster.test_cluster[0].name
  addon_name        = "kube-proxy"
  addon_version     = var.eks_kube_proxy_version
  resolve_conflicts = "OVERWRITE"

tags = {
  Name = "test-eks-kube-proxy-addon"  
}
}
## coredns
resource "aws_eks_addon" "coredns" {
  count = min(local.total_node_pool_count, 1)

  cluster_name      = aws_eks_cluster.test_cluster[0].name
  addon_name        = "coredns"
  addon_version     = var.eks_coredns_version
  resolve_conflicts = "OVERWRITE"

  # coredns needs nodes to run on, so don't create it until
  # the node-pools have been created
  depends_on = [
    aws_eks_node_group.test_pool
  ]

tags = {
  Name = "test-eks-coredns-addon"
}
}
## vpc-cni

resource "aws_eks_addon" "vpc_cni" {
  count = min(local.total_node_pool_count, 1)

  cluster_name             = aws_eks_cluster.test_cluster[0].name
  addon_name               = "vpc-cni"
  addon_version            = var.eks_vpc_cni_version 
  service_account_role_arn = aws_iam_role.test_addon_vpc_cni_role[count.index].arn
  resolve_conflicts        = "OVERWRITE"

  depends_on = [
    aws_eks_addon.kube_proxy,
    # Note: To specify an existing IAM role, you must have an IAM OpenID Connect (OIDC) provider created for your cluster.
    aws_iam_openid_connect_provider.test_cluster_openid
  ]
tags = {
  Name = "test-addon-vpc-cni"  
}
}
resource "aws_iam_role" "test_addon_vpc_cni_role" {
  count = min(local.total_node_pool_count, 1)
  name  = "test_addon_vpc_cni_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRoleWithWebIdentity"
        Effect    = "Allow"
        Principal = { Federated = aws_iam_openid_connect_provider.test_cluster_openid[count.index].arn }
        Condition = {
          "StringEquals" = {
            "${replace(aws_iam_openid_connect_provider.test_cluster_openid[count.index].url, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-node"
          }
        }
      },
    ]
  })

  path                 = var.default_iam_identifier_path
  permissions_boundary = var.default_iam_permissions_boundary_arn
  tags = {
     Name = "test-addon-vpc-cni-role"    
  }
}
resource "aws_iam_role_policy_attachment" "test_addon_vpc_cni_policy" {
  count = min(local.total_node_pool_count, 1)

  policy_arn = "arn:${local.aws_partition}:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.test_addon_vpc_cni_role[count.index].name
}
## IAM OIDC provider for required addons
data "tls_certificate" "test_cluster_oidc" {
  count = min(local.total_node_pool_count, 1)

  url = aws_eks_cluster.test_cluster[0].identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "test_cluster_openid" {
  count = min(local.total_node_pool_count, 1)

  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.test_cluster_oidc[count.index].certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.test_cluster[0].identity[0].oidc[0].issuer
  tags = {
     Name = "test-cluster-openid"
  }

}

output "kubernetes" {
  value = {
    "kubernetes_cluster_name"    = try(aws_eks_cluster.test_cluster[0].name, "")
    "kubernetes_cluster_version" = try(aws_eks_cluster.test_cluster[0].version, "")
    
     # Expose All Roles created for EKS
    "kubernetes_eks_role"           = try(aws_iam_role.test_eks_role[0].name, "")
    "kubernetes_eks_node_role"      = try(aws_iam_role.test_eks_node_role[0].name, "")

     # Node Group / Addon Versions
    "kubernetes_test_node_group_ami_release_version" = try(aws_eks_node_group.test_pool[0].release_version, "")

    "kubernetes_addon_kube_proxy_version" = try(aws_eks_addon.kube_proxy[0].addon_version, "")
    "kubernetes_addon_coredns_version"    = try(aws_eks_addon.coredns[0].addon_version, "")
  }
}
