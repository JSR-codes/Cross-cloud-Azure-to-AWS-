## This is the AWS side MGN needs in place before you can even start
## replicating: a staging area for incoming replicated data, and a
## target subnet for the cutover instance once migration completes.

resource "aws_vpc" "target" {
  cidr_block           = var.aws_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.project_name}-target-vpc" }
}

resource "aws_internet_gateway" "target" {
  vpc_id = aws_vpc.target.id
  tags   = { Name = "${var.project_name}-target-igw" }
}

resource "aws_subnet" "staging" {
  vpc_id                  = aws_vpc.target.id
  cidr_block              = var.aws_staging_subnet_cidr
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.project_name}-mgn-staging-subnet" }
}

resource "aws_subnet" "target" {
  vpc_id                  = aws_vpc.target.id
  cidr_block              = var.aws_target_subnet_cidr
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.project_name}-cutover-subnet" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.target.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.target.id
  }

  tags = { Name = "${var.project_name}-public-rt" }
}

resource "aws_route_table_association" "staging" {
  subnet_id      = aws_subnet.staging.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "target" {
  subnet_id      = aws_subnet.target.id
  route_table_id = aws_route_table.public.id
}

# Security group for the MGN replication servers that land in the staging subnet.
# MGN creates and manages these replication server instances itself once
# initialized - this group just needs to allow the traffic they require.
resource "aws_security_group" "mgn_staging" {
  name        = "${var.project_name}-mgn-staging-sg"
  description = "Allow MGN replication traffic into the staging subnet"
  vpc_id      = aws_vpc.target.id

  ingress {
    description = "TCP 1500 - MGN replication agent traffic"
    from_port   = 1500
    to_port     = 1500
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # tighten to your source's public IP in production
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-mgn-staging-sg" }
}

# Security group for the cutover instance once migration completes.
resource "aws_security_group" "cutover" {
  name        = "${var.project_name}-cutover-sg"
  description = "Security group for the migrated instance after cutover"
  vpc_id      = aws_vpc.target.id

  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-cutover-sg" }
}
