resource "aws_security_group" "efs_sg" {
  name        = "efs-private-sg"
  description = "Allow NFS from VPC only"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "NFS from VPC"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.this.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "efs-private-sg"
  }
}

resource "aws_efs_file_system" "this" {
  creation_token = "efs-private"

  encrypted        = true
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  tags = {
    Name = "efs-private"
  }
}

resource "aws_efs_mount_target" "private_az1" {
  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = aws_subnet.private_subnet_1.id
  security_groups = [aws_security_group.efs_sg.id]
}

resource "aws_efs_mount_target" "private_az2" {
  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = aws_subnet.private_subnet_2.id
  security_groups = [aws_security_group.efs_sg.id]
}

resource "time_sleep" "wait_ec2_ready" {
  depends_on = [
    aws_instance.ssm_test
  ]

  create_duration = "3m"
}


resource "aws_ssm_document" "mount_efs" {
  name          = "MountEfsAndWriteData"
  document_type = "Command"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Mount EFS and write test files"
    parameters = {
      efsId = {
        type        = "String"
        description = "EFS File System ID"
      }
      mountPoint = {
        type        = "String"
        default     = "/mnt/efs"
      }
    }
    mainSteps = [
      {
        action = "aws:runShellScript"
        name   = "mountEfs"
        inputs = {
          runCommand = [
            "set -e",
            "yum install -y amazon-efs-utils",
            "mkdir -p {{ mountPoint }}",
            "mount -t efs {{ efsId }}:/ {{ mountPoint }}",
            "echo '{{ efsId }}:/ {{ mountPoint }} efs _netdev,tls 0 0' >> /etc/fstab",
            "mkdir -p {{ mountPoint }}/v1 {{ mountPoint }}/v2",
            "echo \"DATA V1 FROM EFS $(date)\" > {{ mountPoint }}/v1/data.txt",
            "echo \"DATA V2 FROM EFS $(date)\" > {{ mountPoint }}/v2/data.txt"
          ]
        }
      }
    ]
  })
}

resource "aws_ssm_association" "mount_efs" {
  name = aws_ssm_document.mount_efs.name

  targets {
    key    = "InstanceIds"
    values = [aws_instance.ssm_test.id]
  }

  parameters = {
    efsId      = aws_efs_file_system.this.id
    mountPoint = "/mnt/efs"
  }

  depends_on = [
    time_sleep.wait_ec2_ready,
    aws_efs_mount_target.private_az1,
    aws_efs_mount_target.private_az2
  ]
}
