# Module: lambda

Creates an AWS Lambda function with its CloudWatch Log Group and optional invocation permissions.

## Resources created

| Resource | Description |
|---|---|
| `aws_lambda_function.this` | Lambda function |
| `aws_cloudwatch_log_group.this` | Log group `/aws/lambda/<function_name>` |
| `aws_lambda_permission.this` | One permission per entry in `var.permissions` |

---

## Usage

### Minimal — deploy desde archivo local

```hcl
module "lambda" {
  source = "../modules/lambda"

  function_name = "my-function"
  role_arn      = module.iam.role_arn
  filename      = "${path.module}/dist/function.zip"
}
```

---

### Con variables de entorno y despliegue desde S3

```hcl
module "lambda" {
  source = "../modules/lambda"

  function_name    = "my-function"
  runtime          = "nodejs20.x"
  handler          = "index.handler"
  role_arn         = module.iam.role_arn
  memory_size      = 256
  timeout          = 60

  s3_bucket        = "my-deployment-bucket"
  s3_key           = "functions/my-function.zip"
  source_code_hash = filebase64sha256("dist/function.zip")

  environment_variables = {
    NODE_ENV   = "production"
    TABLE_NAME = module.dynamodb.table_name
  }

  tags = {
    environment = "production"
    project     = "ctv"
  }
}
```

---

### Con permisos de invocación (API Gateway + Cognito)

```hcl
module "lambda" {
  source = "../modules/lambda"

  function_name = "my-function"
  role_arn      = module.iam.role_arn
  filename      = "${path.module}/dist/function.zip"

  permissions = {
    allow_api_gateway = {
      action     = "lambda:InvokeFunction"
      principal  = "apigateway.amazonaws.com"
      source_arn = "${module.api_gateway.execution_arn}/*/*"
    }
    allow_cognito = {
      action     = "lambda:InvokeFunction"
      principal  = "cognito-idp.amazonaws.com"
      source_arn = module.cognito.user_pool_arn
    }
  }
}
```

---

### Con permiso de EventBridge

```hcl
module "lambda" {
  source = "../modules/lambda"

  function_name = "my-scheduler"
  role_arn      = module.iam.role_arn
  filename      = "${path.module}/dist/scheduler.zip"

  permissions = {
    allow_eventbridge = {
      action     = "lambda:InvokeFunction"
      principal  = "events.amazonaws.com"
      source_arn = aws_cloudwatch_event_rule.this.arn
    }
  }
}
```

---

## Variables

| Name | Type | Default | Description |
|---|---|---|---|
| `function_name` | `string` | — | Nombre de la función Lambda |
| `runtime` | `string` | `nodejs20.x` | Runtime de Lambda |
| `handler` | `string` | `index.handler` | Entrypoint del handler |
| `role_arn` | `string` | — | ARN del IAM role de ejecución |
| `filename` | `string` | `null` | Path local al ZIP de despliegue |
| `s3_bucket` | `string` | `null` | Bucket S3 con el paquete de despliegue |
| `s3_key` | `string` | `null` | Key S3 del paquete de despliegue |
| `source_code_hash` | `string` | `null` | Hash SHA256 en base64 del paquete |
| `memory_size` | `number` | `128` | Memoria en MB |
| `timeout` | `number` | `30` | Tiempo máximo de ejecución en segundos |
| `environment_variables` | `map(string)` | `{}` | Variables de entorno |
| `log_retention_days` | `number` | `14` | Días de retención de logs en CloudWatch |
| `permissions` | `map(object)` | `{}` | Permisos de invocación (ver abajo) |
| `tags` | `map(string)` | `{}` | Tags aplicados a los recursos |

### Estructura de `permissions`

```hcl
permissions = {
  "<statement_id>" = {
    action         = string           # e.g. "lambda:InvokeFunction"
    principal      = string           # e.g. "apigateway.amazonaws.com"
    source_arn     = optional(string) # ARN del recurso que puede invocar
    source_account = optional(string) # Account ID para restringir el acceso
  }
}
```

La clave del mapa se usa como `statement_id` en el `aws_lambda_permission`.

---

## Outputs

| Name | Description |
|---|---|
| `function_arn` | ARN de la función Lambda |
| `function_name` | Nombre de la función Lambda |
| `invoke_arn` | Invoke ARN (usado por API Gateway) |

---

## Notas

- `filename` y `s3_bucket`/`s3_key` son mutuamente excluyentes — usa uno u otro.
- El log group se crea antes que la función para evitar que Lambda lo cree sin retención configurada.
- Terraform `>= 1.3.0` es requerido para el uso de `optional()` en el tipo de `permissions`.
