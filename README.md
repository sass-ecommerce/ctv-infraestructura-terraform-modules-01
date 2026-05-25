# ctv-infraestructura-terraform-modules-01

Biblioteca de módulos Terraform reutilizables para la infraestructura AWS de Chapa Tu Venta.

## Módulos disponibles

| Módulo                | Recursos AWS                                                                       |
| --------------------- | ---------------------------------------------------------------------------------- |
| `modules/s3`          | S3 bucket con SSE-AES256, bloqueo de acceso público y versionado                   |
| `modules/cognito`     | User Pool + App Client (auth por email, atributos `custom:id` y `custom:tenantId`) |
| `modules/lambda`      | Lambda function + CloudWatch Log Group + permiso de invocación                     |
| `modules/api_gateway` | HTTP API v2 con integración Lambda proxy (ruta `$default`)                         |
| `modules/dynamodb`    | Tabla DynamoDB en modo `PAY_PER_REQUEST`                                           |
| `modules/iam`         | IAM Role + Policy + attachment (1:1)                                               |
| `modules/secrets`     | Secrets Manager + SSM Parameter Store (ruta `/<env>/<app>/<key>`)                  |

## Prerrequisitos

- Terraform >= 1.3.0
- AWS Provider ~> 6.0
- Credenciales AWS configuradas (`aws configure` o variables de entorno)

---

## Cómo referenciar los módulos desde otro repositorio

Usa la fuente Git con el prefijo `git::` y doble barra `//` para indicar el subdirectorio del módulo. Se recomienda fijar siempre un `ref` (tag, branch o commit SHA) para garantizar reproducibilidad.

```hcl
module "mi_bucket" {
  source = "git::ssh://git@github.com/sass-ecommerce/ctv-infraestructura-terraform-modules-01.git//modules/s3?ref=main"

  bucket_name = "ctv-uploads-dev"
  environment = "dev"
}
```

> Después de agregar o cambiar un módulo `source`, ejecutar `terraform init` para que Terraform descargue la fuente.

---

## Uso por módulo

### `s3`

```hcl
module "uploads" {
  source = "git::ssh://git@github.com/sass-ecommerce/ctv-infraestructura-terraform-modules-01.git//modules/s3?ref=main"

  bucket_name       = "ctv-uploads-dev"
  environment       = "dev"
  enable_versioning = true

  tags = {
    Project = "ctv"
    Team    = "backend"
  }
}

# Outputs disponibles:
# module.uploads.bucket_id
# module.uploads.bucket_arn
# module.uploads.bucket_name
```

---

### `dynamodb`

```hcl
module "tabla_productos" {
  source = "git::ssh://git@github.com/sass-ecommerce/ctv-infraestructura-terraform-modules-01.git//modules/dynamodb?ref=main"

  table_name = "ctv-productos-dev"
  hash_key   = "tenantId"

  # Sort key opcional
  range_key      = "productId"
  range_key_type = "S"

  # Activar PITR en producción
  enable_point_in_time_recovery = false

  tags = { Environment = "dev" }
}

# Outputs disponibles:
# module.tabla_productos.table_name
# module.tabla_productos.table_arn
# module.tabla_productos.table_id
```

> El módulo no soporta GSI/LSI. Si los necesitas, agrega bloques `global_secondary_index` directamente en el `main.tf` del módulo o extiende el `variables.tf`.

---

### `iam`

```hcl
module "rol_lambda" {
  source = "git::ssh://git@github.com/sass-ecommerce/ctv-infraestructura-terraform-modules-01.git//modules/iam?ref=main"

  role_name           = "ctv-lambda-productos-dev"
  assume_role_service = "lambda.amazonaws.com"
  policy_name         = "ctv-lambda-productos-policy-dev"

  # Incluye TODOS los permisos que necesita el Lambda en este JSON
  policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Query"]
        Resource = module.tabla_productos.table_arn
      }
    ]
  })

  tags = { Environment = "dev" }
}

# Outputs disponibles:
# module.rol_lambda.role_arn
# module.rol_lambda.role_name
# module.rol_lambda.policy_arn
```

> Este módulo crea un rol y una política propia (1:1). No soporta adjuntar AWS Managed Policies. Incluye los permisos de CloudWatch Logs dentro del `policy_json` si el Lambda necesita escribir logs.

---

### `lambda`

Soporta dos modos de despliegue: ZIP local o desde S3. Usa uno solo por función.

**Desde un archivo ZIP local:**

```hcl
module "lambda_productos" {
  source = "git::ssh://git@github.com/sass-ecommerce/ctv-infraestructura-terraform-modules-01.git//modules/lambda?ref=main"

  function_name    = "ctv-productos-dev"
  role_arn         = module.rol_lambda.role_arn
  filename         = "${path.module}/dist/productos.zip"
  source_code_hash = filebase64sha256("${path.module}/dist/productos.zip")

  runtime = "nodejs20.x"
  handler = "index.handler"
  timeout = 30

  environment_variables = {
    TABLE_NAME  = module.tabla_productos.table_name
    ENVIRONMENT = "dev"
  }

  # Conceder permiso de invocación desde API Gateway
  api_gateway_execution_arn = module.api.execution_arn

  tags = { Environment = "dev" }
}
```

**Desde S3:**

```hcl
module "lambda_productos" {
  source = "git::ssh://git@github.com/sass-ecommerce/ctv-infraestructura-terraform-modules-01.git//modules/lambda?ref=main"

  function_name    = "ctv-productos-dev"
  role_arn         = module.rol_lambda.role_arn
  s3_bucket        = "ctv-deployments-dev"
  s3_key           = "lambdas/productos/v1.0.0.zip"
  source_code_hash = "..."   # base64sha256 del ZIP

  runtime = "nodejs20.x"
  handler = "index.handler"

  tags = { Environment = "dev" }
}
```

> Usa `filename` o `s3_bucket`/`s3_key`, nunca ambos al mismo tiempo.

```
# Outputs disponibles:
# module.lambda_productos.function_arn
# module.lambda_productos.function_name
# module.lambda_productos.invoke_arn
```

---

### `api_gateway`

```hcl
module "api" {
  source = "git::ssh://git@github.com/sass-ecommerce/ctv-infraestructura-terraform-modules-01.git//modules/api_gateway?ref=main"

  api_name          = "ctv-api-dev"
  lambda_invoke_arn = module.lambda_productos.invoke_arn
  stage_name        = "$default"

  tags = { Environment = "dev" }
}

# Outputs disponibles:
# module.api.api_id
# module.api.api_endpoint
# module.api.execution_arn    <- necesario para module.lambda_productos.api_gateway_execution_arn
# module.api.stage_invoke_url <- URL pública del API
```

> Este módulo crea una sola ruta `$default` que captura todos los paths y métodos HTTP. El routing interno (e.g., `/productos`, `/ordenes`) debe manejarse dentro del Lambda. CORS no está configurado en el API Gateway; debe responderse desde el Lambda si el cliente es un navegador.

---

### `cognito`

```hcl
module "auth" {
  source = "git::ssh://git@github.com/sass-ecommerce/ctv-infraestructura-terraform-modules-01.git//modules/cognito?ref=main"

  name            = "ctv-users-dev"
  app_client_name = "ctv-web-client-dev"

  password_min_length = 8

  # Opcional: Lambda triggers
  pre_token_generation_lambda_arn = module.lambda_pre_token.function_arn
  post_confirmation_lambda_arn    = module.lambda_post_confirm.function_arn

  tags = { Environment = "dev" }
}

# Outputs disponibles:
# module.auth.user_pool_id
# module.auth.user_pool_arn
# module.auth.client_id
```

> El User Pool usa email como username, MFA desactivado y cliente público (`generate_secret = false`). Los atributos `custom:id` y `custom:tenantId` vienen configurados por defecto para soporte multi-tenant.

---

### `secrets`

```hcl
module "config" {
  source = "git::ssh://git@github.com/sass-ecommerce/ctv-infraestructura-terraform-modules-01.git//modules/secrets?ref=main"

  environment = "dev"
  app_name    = "ctv"

  # Secrets Manager — para valores que rotan o son consultados en runtime
  secrets = {
    stripe_api_key    = var.stripe_api_key
    jwt_secret        = var.jwt_secret
  }

  # SSM SecureString — para configs sensibles (contraseñas, tokens)
  parameters = {
    db_password = var.db_password
  }

  # SSM String — para configs no sensibles (URLs, nombres)
  string_parameters = {
    cognito_user_pool_id = module.auth.user_pool_id
    cognito_client_id    = module.auth.client_id
  }

  tags = { Environment = "dev" }
}

# Outputs disponibles:
# module.config.secret_arns      # map key → ARN en Secrets Manager
# module.config.parameter_arns   # map key → ARN en SSM
# module.config.parameter_names  # map key → path completo en SSM (/<env>/<app>/<key>)
```

> Los valores en `secrets` y `parameters` son `sensitive = true`. No los imprimas en outputs de módulos raíz sin marcarlos también como `sensitive`.

---

## Ejemplo completo: Lambda + API Gateway + DynamoDB

Estructura sugerida para un repositorio consumidor:

```
mi-servicio-infraestructura/
├── main.tf
├── variables.tf
├── outputs.tf
├── providers.tf
└── terraform.tfvars       # ignorado por .gitignore
```

**`providers.tf`**

```hcl
terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
```

**`main.tf`**

```hcl
locals {
  env     = var.environment
  app     = "ctv-productos"
  modules = "git::ssh://git@github.com/sass-ecommerce/ctv-infraestructura-terraform-modules-01.git//modules"
  ref     = "?ref=main"
}

module "tabla" {
  source = "${local.modules}/dynamodb${local.ref}"

  table_name = "${local.app}-${local.env}"
  hash_key   = "tenantId"
  range_key  = "productId"
  enable_point_in_time_recovery = local.env == "prod"

  tags = { Environment = local.env }
}

module "rol" {
  source = "${local.modules}/iam${local.ref}"

  role_name           = "${local.app}-lambda-${local.env}"
  assume_role_service = "lambda.amazonaws.com"
  policy_name         = "${local.app}-lambda-policy-${local.env}"

  policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Query", "dynamodb:DeleteItem"]
        Resource = module.tabla.table_arn
      }
    ]
  })

  tags = { Environment = local.env }
}

module "api" {
  source = "${local.modules}/api_gateway${local.ref}"

  api_name          = "${local.app}-${local.env}"
  lambda_invoke_arn = module.lambda.invoke_arn

  tags = { Environment = local.env }
}

module "lambda" {
  source = "${local.modules}/lambda${local.ref}"

  function_name    = "${local.app}-${local.env}"
  role_arn         = module.rol.role_arn
  filename         = "${path.module}/dist/handler.zip"
  source_code_hash = filebase64sha256("${path.module}/dist/handler.zip")
  runtime          = "nodejs20.x"
  handler          = "index.handler"

  api_gateway_execution_arn = module.api.execution_arn

  environment_variables = {
    TABLE_NAME  = module.tabla.table_name
    ENVIRONMENT = local.env
  }

  tags = { Environment = local.env }
}
```

> `module.api` y `module.lambda` tienen una dependencia circular parcial (`execution_arn` del API hacia el Lambda, `invoke_arn` del Lambda hacia el API). Terraform resuelve esto correctamente porque cada uno referencia un output diferente del otro.

**`outputs.tf`**

```hcl
output "api_url" {
  value = module.api.stage_invoke_url
}

output "lambda_name" {
  value = module.lambda.function_name
}
```

---

## Versionado

Se recomienda usar tags de Git para fijar versiones estables en los repositorios consumidores:

```hcl
source = "git::ssh://git@github.com/sass-ecommerce/ctv-infraestructura-terraform-modules-01.git//modules/lambda?ref=v1.2.0"
```

Para crear un tag:

```bash
git tag v1.0.0
git push origin v1.0.0
```
