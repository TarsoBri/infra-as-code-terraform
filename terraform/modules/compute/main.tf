# ECR repository — stores Docker images for the Go API, tagged by commit SHA
resource "aws_ecr_repository" "app" {
  name                 = "go-crud-${var.env}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Lifecycle policy — keeps only the last 10 images to control storage costs
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

# ECS cluster — logical grouping for all Fargate tasks in this environment
resource "aws_ecs_cluster" "main" {
  name = "${var.env}-cluster"
}

# CloudWatch log group — collects stdout/stderr from all Go API containers
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.env}/go-crud"
  retention_in_days = 7
}

# ECS task definition — blueprint for each container: CPU, memory, image, secrets, and log config
resource "aws_ecs_task_definition" "app" {
  family                   = "${var.env}-go-crud"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = var.ecs_execution_role_arn
  task_role_arn            = var.ecs_task_role_arn

  container_definitions = jsonencode([{
    name  = "go-crud"
    image = var.container_image

    portMappings = [{
      containerPort = 8080
      protocol      = "tcp"
    }]

    # Secrets fetched from Secrets Manager by the execution role before the container starts
    secrets = [
      { name = "DB_PASSWORD", valueFrom = var.db_password_secret_arn },
      { name = "DB_USERNAME", valueFrom = var.db_username_secret_arn }
    ]

    # Non-sensitive config values passed as plain environment variables
    environment = [
      { name = "APP_PORT", value = "8080" },
      { name = "ENV", value = var.env },
      { name = "DB_HOST", value = var.db_endpoint },
      { name = "DB_PORT", value = "5432" },
      { name = "DB_NAME", value = "gocrud" },
      { name = "REDIS_ADDR", value = "${var.redis_endpoint}:6379" }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/${var.env}/go-crud"
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "go-crud"
      }
    }

    # ALB uses this health check to decide if the task is ready to receive traffic
    healthCheck = {
      command     = ["CMD-SHELL", "curl -f http://localhost:8080/health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }
  }])
}

# ALB — internet-facing load balancer in public subnets that routes traffic to ECS
resource "aws_lb" "main" {
  name               = "${var.env}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.sg_alb_id]
  subnets            = var.public_subnet_ids
}

# Target group — the ALB sends requests here; ECS registers tasks as targets automatically
resource "aws_lb_target_group" "app" {
  name        = "${var.env}-go-crud-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
  }
}

# ALB listener — accepts HTTP on port 80 and forwards requests to the target group
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# ECS service — keeps min_tasks running at all times and registers them with the ALB
resource "aws_ecs_service" "app" {
  name            = "${var.env}-go-crud"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.min_tasks
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.sg_ecs_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "go-crud"
    container_port   = 8080
  }

  # Listener must exist before the service starts registering targets
  depends_on = [aws_lb_listener.http]
}

# Auto Scaling target — registers this ECS service as a scalable resource
resource "aws_appautoscaling_target" "app" {
  max_capacity       = var.max_tasks
  min_capacity       = var.min_tasks
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Auto Scaling policy — adds tasks when average CPU exceeds 60%, removes them when it drops
resource "aws_appautoscaling_policy" "cpu" {
  name               = "${var.env}-cpu-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.app.resource_id
  scalable_dimension = aws_appautoscaling_target.app.scalable_dimension
  service_namespace  = aws_appautoscaling_target.app.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = 60.0
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}
