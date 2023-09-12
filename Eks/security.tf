data "aws_vpc" "selected" {
  id = aws_vpc.test_vpc[0].id
}

resource "aws_security_group" "test_internal_networking" {
  count = var.test_internal_networking ? 1 : 0
  name   = "test-internal-networking"
  vpc_id = data.aws_vpc.selected.id
  
  ingress {
    description = "Open internal networking for VMs"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
    cidr_blocks = [var.vpc_cidr_block]
  }

  egress {
    description = "Open internet access for VMs"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "test-internal-networking"
  }
}

