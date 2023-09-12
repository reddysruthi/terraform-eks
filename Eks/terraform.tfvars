######### network ##########
region = "us-east-1"
create_network = true
allowed_zones = ["us-east-1a", "us-east-1b"]
vpc_cidr_block = "10.96.8.0/21"
subnet_pub_cidr_block = ["10.96.8.0/27", "10.96.8.32/27"]
subnet_priv_cidr_block = ["10.96.10.0/24", "10.96.11.0/24", "10.96.12.0/23", "10.96.14.0/23"]

########### security ###########
create_security_group = true
test_internal_networking = true


############## eks ###########
eks_ami_id=  "ami-043d113d70529a888"
test_node_pool_count = 2
test_node_pool_max_count = 4
eks_version = 1.26
eks_endpoint_public_access_cidr_blocks = ["0.0.0.0/0"]
eks_endpoint_public_access = true
eks_endpoint_private_access = true
eks_envelope_encryption = true
test_node_pool_disk_size = 30
test_node_pool_min_count = 2
test_node_pool_desired_count = 1
test_node_pool_instance_type = "t2.medium"
eks_kube_proxy_version = "v1.26.2-eksbuild.1"
eks_coredns_version = "v1.9.3-eksbuild.5"
ekscluster_name = "test-cluster-demo"
eks_vpc_cni_version = "v1.12.6-eksbuild.2"