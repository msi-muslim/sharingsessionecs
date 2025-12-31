# Security Group (no inbound, allow all outbound)
resource "aws_security_group" "ec2_ssm_sg" {
  name        = "ec2-ssm-sg"
  description = "SG for EC2 SSM only"
  vpc_id      = aws_vpc.this.id

  # NO INBOUND RULES

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ec2-ssm-sg"
  }
}

# EC2 Instance
resource "aws_instance" "ssm_test" {
  ami                    = "ami-073a4494f1914921f"
  instance_type          = "t3.nano"
  subnet_id = aws_subnet.private_subnet_1.id
  vpc_security_group_ids = [aws_security_group.ec2_ssm_sg.id]

  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.ec2_ssm_profile.name

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
  }

  tags = {
    Name = "ec2-ssm-test"
  }
    
  
  depends_on = [ aws_nat_gateway.this,aws_efs_mount_target.private_az1,aws_efs_mount_target.private_az2 ]
}
