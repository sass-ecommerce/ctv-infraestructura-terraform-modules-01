# S3 Module

Crea un bucket S3 con cifrado AES256, bloqueo total de acceso público y versionado configurable. Opcionalmente permite configurar notificaciones hacia Lambda, SQS, SNS o EventBridge.

## Recursos creados

| Recurso | Descripción |
|---|---|
| `aws_s3_bucket` | Bucket principal |
| `aws_s3_bucket_versioning` | Versionado habilitado o suspendido |
| `aws_s3_bucket_server_side_encryption_configuration` | Cifrado AES256 por defecto |
| `aws_s3_bucket_public_access_block` | Bloqueo completo de acceso público |
| `aws_s3_bucket_notification` | Notificaciones (solo si se configura al menos una) |

## Uso básico

```hcl
module "s3" {
  source = "../../modules/s3"

  bucket_name = "ctv-uploads-prod"
  environment = "prod"
}
```

## Con notificación a Lambda

```hcl
module "s3" {
  source = "../../modules/s3"

  bucket_name = "ctv-uploads-prod"
  environment = "prod"

  lambda_notifications = [
    {
      lambda_function_arn = module.lambda.function_arn
      events              = ["s3:ObjectCreated:*"]
      filter_prefix       = "uploads/"
      filter_suffix       = ".json"
    }
  ]
}
```

> **Nota:** Antes de aplicar, asegúrate de que la función Lambda tenga un `aws_lambda_permission` que permita que S3 la invoque. Ver [permisos de invocación](#permisos-de-invocación).

## Con notificación a SQS

```hcl
module "s3" {
  source = "../../modules/s3"

  bucket_name = "ctv-events-prod"
  environment = "prod"

  sqs_notifications = [
    {
      queue_arn     = aws_sqs_queue.my_queue.arn
      events        = ["s3:ObjectCreated:*", "s3:ObjectRemoved:*"]
      filter_prefix = "data/"
    }
  ]
}
```

## Con notificación a SNS

```hcl
module "s3" {
  source = "../../modules/s3"

  bucket_name = "ctv-reports-prod"
  environment = "prod"

  sns_notifications = [
    {
      topic_arn = aws_sns_topic.my_topic.arn
      events    = ["s3:ObjectCreated:*"]
    }
  ]
}
```

## Con EventBridge

```hcl
module "s3" {
  source = "../../modules/s3"

  bucket_name        = "ctv-audit-prod"
  environment        = "prod"
  enable_eventbridge = true
}
```

## Con múltiples destinos y versionado deshabilitado

```hcl
module "s3" {
  source = "../../modules/s3"

  bucket_name       = "ctv-mixed-prod"
  environment       = "prod"
  enable_versioning = false

  lambda_notifications = [
    {
      lambda_function_arn = module.processor.function_arn
      events              = ["s3:ObjectCreated:Put"]
      filter_suffix       = ".csv"
    }
  ]

  sqs_notifications = [
    {
      queue_arn = aws_sqs_queue.dlq.arn
      events    = ["s3:ObjectRemoved:*"]
    }
  ]

  tags = {
    Team    = "backend"
    Project = "ctv"
  }
}
```

## Permisos de invocación

Al usar `lambda_notifications`, S3 necesita permiso para invocar la función. Esto se gestiona fuera de este módulo con `aws_lambda_permission`:

```hcl
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = module.lambda.function_arn
  principal     = "s3.amazonaws.com"
  source_arn    = module.s3.bucket_arn
}
```

El módulo `lambda` de este repositorio expone la variable `invocation_permissions` para declarar esto de forma centralizada.

## Variables

| Variable | Tipo | Requerida | Default | Descripción |
|---|---|---|---|---|
| `bucket_name` | `string` | sí | — | Nombre del bucket |
| `environment` | `string` | sí | — | Entorno de despliegue (`dev`, `prod`) |
| `enable_versioning` | `bool` | no | `true` | Habilita el versionado del bucket |
| `enable_eventbridge` | `bool` | no | `false` | Envía todos los eventos del bucket a EventBridge |
| `lambda_notifications` | `list(object)` | no | `[]` | Notificaciones hacia funciones Lambda |
| `sqs_notifications` | `list(object)` | no | `[]` | Notificaciones hacia colas SQS |
| `sns_notifications` | `list(object)` | no | `[]` | Notificaciones hacia tópicos SNS |
| `tags` | `map(string)` | no | `{}` | Tags adicionales aplicados al bucket |

### Estructura de `lambda_notifications` / `sqs_notifications` / `sns_notifications`

Todos comparten la misma forma, cambiando solo el campo del ARN:

| Campo | Tipo | Requerido | Descripción |
|---|---|---|---|
| `lambda_function_arn` / `queue_arn` / `topic_arn` | `string` | sí | ARN del destino |
| `events` | `list(string)` | sí | Eventos S3 que disparan la notificación (ej. `s3:ObjectCreated:*`) |
| `filter_prefix` | `string` | no | Filtra por prefijo de clave (ej. `uploads/`) |
| `filter_suffix` | `string` | no | Filtra por sufijo de clave (ej. `.json`) |

## Outputs

| Output | Descripción |
|---|---|
| `bucket_id` | ID del bucket (igual al nombre) |
| `bucket_arn` | ARN del bucket |
| `bucket_name` | Nombre del bucket |
