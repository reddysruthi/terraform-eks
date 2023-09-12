data "aws_availability_zones" "defaults" {
  state = "available"

  filter {
    name   = "zone-name"
    values = var.allowed_zones
  }
}

#Create Network
resource "aws_vpc" "test_vpc" {
  count                = var.create_network ? 1 : 0
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.map_tag,{
    Name = "test-vpc"
  })
}

## Public Subnet(s)
resource "aws_subnet" "test_vpc_sn_pub" {
  count                   = length(var.subnet_pub_cidr_block)
  vpc_id                  = aws_vpc.test_vpc[0].id
  cidr_block              = var.subnet_pub_cidr_block[count.index]
  availability_zone       = element(data.aws_availability_zones.defaults.names, count.index)
  map_public_ip_on_launch = true

  timeouts {
    delete = "30m"
  }
  tags = merge(var.map_tag,{
    Name = "test-sub-pub-${count.index + 1}"
    "kubernetes.io/role/elb" = 1
  })
}

resource "aws_internet_gateway" "test_vpc_gw" {
  count  = var.create_network ? 1 : 0
  vpc_id = aws_vpc.test_vpc[0].id

  tags = merge(var.map_tag,{
    Name = "test-igw"
  })
}

resource "aws_route_table" "test_vpc_route_table_pub" {
  count = var.create_network_routes ?  1 : 0

  vpc_id = aws_vpc.test_vpc[0].id

  tags = {
    Name = "test-pub-rt"
  }
}

# The default internet route via Internet Gateway
resource "aws_route" "test_vpc_route_pub_igw" {
  count = var.create_network_routes ?  1 : 0

  route_table_id         = aws_route_table.test_vpc_route_table_pub[0].id
  destination_cidr_block = "0.0.0.0/0" # Internet Access
  gateway_id             = aws_internet_gateway.test_vpc_gw[0].id
}

resource "aws_route_table_association" "test_vpc_route_table_association_pub" {
  count = var.create_network_routes ? length(var.subnet_pub_cidr_block) : 0

  subnet_id      = aws_subnet.test_vpc_sn_pub[count.index].id
  route_table_id = aws_route_table.test_vpc_route_table_pub[0].id
}

## Private Subnet(s)
resource "aws_subnet" "test_vpc_sn_priv" {
  count             = length(var.subnet_priv_cidr_block)
  vpc_id            = aws_vpc.test_vpc[0].id
  cidr_block        = var.subnet_priv_cidr_block[count.index]
  availability_zone = element(data.aws_availability_zones.defaults.names, count.index)
  
  timeouts {
    delete = "30m"
  }
  tags = merge(var.map_tag,{
    Name  = "test-sub-priv-${count.index + 1}"
    "kubernetes.io/role/internal-elb" = 1
  })
}

### Nat Gateway and IP for Private Subnet(s)
resource "aws_eip" "test_vpc_sn_priv_ng_ip" {
  count = var.create_network ? 1 : 0

  vpc = true
}

resource "aws_nat_gateway" "test_vpc_sn_priv_ng" {
  count = var.create_network ? 1 : 0

  allocation_id = aws_eip.test_vpc_sn_priv_ng_ip[count.index].id
  subnet_id     = aws_subnet.test_vpc_sn_pub[count.index].id

  tags = merge(var.map_tag,{
    Name = "test-sub-priv-nat"
  })
}

resource "aws_route_table" "test_vpc_route_table_priv" {
  count = var.create_network_routes ? 1 : 0

  vpc_id = aws_vpc.test_vpc[0].id

  tags = merge(var.map_tag,{
    Name = "test-sub-priv-rt"
  })
}

# The default internet route via NAT Gateway
resource "aws_route" "test_vpc_route_priv_nat" {
  count = var.create_network_routes ? 1 : 0

  route_table_id         = aws_route_table.test_vpc_route_table_priv[count.index].id
  destination_cidr_block = "0.0.0.0/0" # Internet Access
  nat_gateway_id         = aws_nat_gateway.test_vpc_sn_priv_ng[count.index].id
}
resource "aws_route_table_association" "test_vpc_route_table_association_priv" {
  count = var.create_network_routes ? length(var.subnet_priv_cidr_block) : 0

  subnet_id      = aws_subnet.test_vpc_sn_priv[count.index].id
  route_table_id = aws_route_table.test_vpc_route_table_priv[0].id
}

output "vpc_id" {
  value = aws_vpc.test_vpc[0].id
}
output "subnet_ids" {
  value = aws_subnet.test_vpc_sn_priv.*.id
}
output "securitygroup_ids" {
  value = aws_security_group.test_internal_networking[0].id
}

output "default_zones" {
  value = data.aws_availability_zones.defaults.names
}
