resource "aws_neptune_subnet_group" "this" {
  name       = "neptune"
  subnet_ids = data.aws_subnets.this.ids
}

resource "aws_security_group" "neptune" {
  name   = "neptune"
  vpc_id = data.aws_vpc.this.id

  ingress {
    from_port   = 8182
    to_port     = 8182
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_neptune_cluster" "this" {
  cluster_identifier                  = local.project
  engine                              = "neptune"
  neptune_subnet_group_name           = aws_neptune_subnet_group.this.name
  vpc_security_group_ids              = [aws_security_group.neptune.id]
  iam_database_authentication_enabled = true
  skip_final_snapshot                 = true
  apply_immediately                   = true
}

resource "aws_neptune_cluster_instance" "this" {
  identifier          = local.project
  cluster_identifier  = aws_neptune_cluster.this.id
  engine              = "neptune"
  instance_class      = "db.r6g.large"
  publicly_accessible = true
  apply_immediately   = true
}
