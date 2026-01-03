
resource "aws_iam_role" "ecs_instance_role" {
  name = "ecs-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_instance_policy" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role_policy_attachment" "ecs_ssm" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = "ecs-instance-profile"
  role = aws_iam_role.ecs_instance_role.name
}

resource "aws_ecs_cluster" "this" {
  name = "ecs-ec2-cluster"

  service_connect_defaults {
    namespace = aws_service_discovery_private_dns_namespace.ecs.arn
  }
  
}

resource "aws_security_group" "ecs_ec2_sg" {
  name   = "ecs-ec2-sg"
  vpc_id = aws_vpc.this.id

  ingress {
      from_port       = 0
      to_port         = 65535
      protocol        = "tcp"
      security_groups = [aws_security_group.alb_sg.id]
    }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ecs-ec2-sg"
  }


}
locals {
  ecs_user_data = <<-EOF
    #!/bin/bash
    echo "ECS_CLUSTER=${aws_ecs_cluster.this.name}" >> /etc/ecs/ecs.config
  EOF
}

data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2/recommended/image_id"
}


resource "aws_launch_template" "ecs" {
  name_prefix   = "ecs-ec2-"
  image_id = data.aws_ssm_parameter.ecs_ami.value
  instance_type = "t3.micro"

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_instance_profile.name
  }

  vpc_security_group_ids = [aws_security_group.ecs_ec2_sg.id]

  user_data = base64encode(local.ecs_user_data)

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 30
      volume_type           = "gp3"
      delete_on_termination = true
    }
  }
}

resource "aws_autoscaling_group" "ecs" {
  name                = "ecs-asg"
  desired_capacity    = 2
  max_size            = 2
  min_size            = 1
  vpc_zone_identifier = [
    aws_subnet.private_subnet_1.id,
    aws_subnet.private_subnet_2.id
  ]

  launch_template {
    id      = aws_launch_template.ecs.id
    version = "$Latest"
  }

  tag {
    key                 = "AmazonECSManaged"
    propagate_at_launch = true
    value = ""
  }
}

resource "aws_ecs_capacity_provider" "this" {
  name = "test-capacity-provider"

  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.ecs.arn

    managed_scaling {
      status          = "ENABLED"
      target_capacity = 100
    }
  }
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name = aws_ecs_cluster.this.name

  capacity_providers = [aws_ecs_capacity_provider.this.name]

  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.this.name
    weight            = 1
  }
}


resource "aws_iam_role" "ecs_execution_role" {
  name = "ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task_role" {
  name = "ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/efs-test"
  retention_in_days = 7
}


resource "aws_ecs_task_definition" "efs_test" {
  family                   = "efs-test-task"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]

  cpu    = "128"
  memory = "256"

  execution_role_arn = aws_iam_role.ecs_execution_role.arn
  task_role_arn      = aws_iam_role.ecs_task_role.arn

  volume {
    name = "efs-volume"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.this.id
      root_directory     = "/v1"
      transit_encryption = "ENABLED"
    }
  }

  container_definitions = jsonencode([
    {
      name      = "efs-test"
      image     = "priahitammsi/ecsharingsession:v1"
      essential = true

      cpu    = 128
      memory = 256

      environment = [
        {
          name  = "EFS_PATH"
          value = "/mnt/efs"
        }
      ]

      portMappings = [
        {
          containerPort = 3000
          hostPort      = 0
          protocol      = "tcp"
        }
      ]

      mountPoints = [
        {
          sourceVolume  = "efs-volume"
          containerPath = "/mnt/efs"
          readOnly      = false
        }
      ]

      healthCheck = {
        command = [
          "CMD-SHELL",
          "node -e \"require('http').get('http://localhost:3000/health', r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))\""
        ]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 10
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/efs-test"
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = {
    Service     = "efs-test-task"
  }
}

resource "aws_ecs_service" "efs_test" {
  name            = "efs-test-service"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.efs_test.arn

  desired_count = 1
  launch_type   = "EC2"

  enable_ecs_managed_tags = true
  propagate_tags          = "SERVICE"

  depends_on = [
    aws_ecs_task_definition.efs_test
  ]

  health_check_grace_period_seconds = 60

  load_balancer {
    target_group_arn = aws_lb_target_group.ecs_tg.arn
    container_name   = "efs-test"
    container_port   = 3000
  }

  tags = {
      service = "efs-test-service"
  }

}

##service auto scaling
resource "aws_appautoscaling_target" "efs_test" {
  service_namespace  = "ecs"
  scalable_dimension = "ecs:service:DesiredCount"

  resource_id = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.efs_test.name}"

  min_capacity = 1
  max_capacity = 3
}

resource "aws_appautoscaling_policy" "efs_test_cpu" {
  name               = "efs-test-cpu-scaling"
  service_namespace  = aws_appautoscaling_target.efs_test.service_namespace
  scalable_dimension = aws_appautoscaling_target.efs_test.scalable_dimension
  resource_id        = aws_appautoscaling_target.efs_test.resource_id

  policy_type = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    target_value = 10
    scale_out_cooldown = 60
    scale_in_cooldown  = 120
  }
}



##buat service connect
resource "aws_service_discovery_private_dns_namespace" "ecs" {
  name        = "ecs.local"
  description = "ECS Service Connect namespace"
  vpc         = aws_vpc.this.id
}


resource "aws_security_group" "ecs_sc_sg" {
  name   = "ecs-sc-sg"
  vpc_id = aws_vpc.this.id

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.this.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_ecs_task_definition" "efs_api_sc" {
  tags = {
    Service     = "efs-api-sc"
  }
  family                   = "efs-api-sc"
  requires_compatibilities = ["EC2"]
  network_mode             = "awsvpc"

  cpu    = "256"
  memory = "512"

  execution_role_arn = aws_iam_role.ecs_execution_role.arn
  task_role_arn      = aws_iam_role.ecs_task_role.arn

  volume {
    name = "efs-volume"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.this.id
      root_directory     = "/v1"
      transit_encryption = "ENABLED"
    }
  }

  container_definitions = jsonencode([
    {
      name      = "efs-api"
      image     = "priahitammsi/ecsharingsession:v2"
      essential = true

      environment = [
        {
          name  = "EFS_PATH"
          value = "/mnt/efs"
        }
      ]

      portMappings = [
        {
          containerPort = 3000
          name          = "http"
          protocol      = "tcp"
        }
      ]

      mountPoints = [
        {
          sourceVolume  = "efs-volume"
          containerPath = "/mnt/efs"
          readOnly      = false
        }
      ]

      healthCheck = {
        command = [
          "CMD-SHELL",
          "node -e \"require('http').get('http://localhost:3000/health', r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))\""
        ]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 10
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/efs-test"
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "efs_api_sc" {
  name            = "efs-api-sc"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.efs_api_sc.arn
  desired_count   = 1
  launch_type     = "EC2"

  network_configuration {
    subnets         = [aws_subnet.private_subnet_1.id,aws_subnet.private_subnet_2.id]
    security_groups = [aws_security_group.ecs_sc_sg.id]
  }

  service_connect_configuration {
    enabled = true

    service {
      port_name      = "http"
      discovery_name = "efs-api"

      client_alias {
        dns_name = "efs-api"
        port     = 3000
      }
    }
  }

    tags = {
      service = "efs-api-sc"
  }

  enable_ecs_managed_tags = true
  propagate_tags          = "SERVICE"

}

resource "aws_ecs_task_definition" "efs_client_sc" {
  family                   = "efs-client-sc"
  requires_compatibilities = ["EC2"]
  network_mode             = "awsvpc"

  cpu    = "128"
  memory = "256"

  execution_role_arn = aws_iam_role.ecs_execution_role.arn
  task_role_arn      = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "client"
      image     = "curlimages/curl:8.5.0"
      essential = true
    
     portMappings = [
        {
          containerPort = 8080   # dummy
          name          = "http"
          protocol      = "tcp"
        }
    ]

     command = [
      "sh",
      "-c",
      "echo 'Testing Service Connect to efs-api'; while true; do date; curl -s http://efs-api:3000/health || echo FAILED; sleep 5; done"
    ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/efs-test"
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
 
  tags = {
    Service     = "efs-client-sc"
  }
}


resource "aws_ecs_service" "efs_client_sc" {
  name            = "efs-client-sc"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.efs_client_sc.arn
  desired_count   = 1
  launch_type     = "EC2"

  network_configuration {
    subnets = [
      aws_subnet.private_subnet_1.id,
      aws_subnet.private_subnet_2.id
    ]
    security_groups = [aws_security_group.ecs_sc_sg.id]
  }

  service_connect_configuration {
      enabled = true

      # service {
      #   port_name      = "http"
      #   discovery_name = "efs-api-client"
      #   client_alias {
      #     dns_name = "efs-api-client"
      #     port     = 3000
      #   }
      # }
    }

  tags = {
      service = "efs-client-sc"
  }
  enable_ecs_managed_tags = true
  propagate_tags          = "SERVICE"
}


