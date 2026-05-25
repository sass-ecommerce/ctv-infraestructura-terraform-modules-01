# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This repository is a **Terraform reusable modules library** for the Chapa Tu Venta (CTV) project. It contains AWS infrastructure modules consumed by root/environment Terraform configurations — there is no root module here, only `modules/`.

## Common Commands

```bash
# Run inside any module directory (e.g., modules/lambda/)
terraform init          # initialize providers
terraform validate      # check syntax and references
terraform fmt           # format files in place
terraform fmt -check    # check formatting without changing files
terraform plan          # preview changes (requires -var or .tfvars)
```

## Module Architecture

Each module follows a strict three-file layout: `main.tf`, `variables.tf`, `outputs.tf`. All resources use `this` as the Terraform resource name. All modules accept a `tags` variable (`map(string)`, default `{}`).

### Modules and their key behaviors

| Module | AWS Services | Notes |
|---|---|---|
| `s3` | S3 | AES256 SSE, public access fully blocked, versioning toggle |
| `cognito` | Cognito User Pool + App Client | Email as username, custom attributes `custom:id` and `custom:tenantId` for multi-tenancy, optional Lambda triggers for `pre_token_generation` and `post_confirmation` |
| `lambda` | Lambda + CloudWatch Logs | Supports local ZIP (`filename`) or S3 deployment (`s3_bucket`/`s3_key`/`source_code_hash`); optional API Gateway invoke permission via `api_gateway_execution_arn` |
| `api_gateway` | API Gateway v2 (HTTP) | Single `$default` route with Lambda proxy integration (`AWS_PROXY`, payload v2.0), `auto_deploy = true` |
| `dynamodb` | DynamoDB | `PAY_PER_REQUEST` billing, optional sort key, optional PITR |
| `iam` | IAM Role + Policy | Creates one role and one inline policy and attaches them (1:1); the caller provides `policy_json` as a rendered JSON string |
| `secrets` | Secrets Manager + SSM | Path convention: `/<environment>/<app_name>/<key>`; supports Secrets Manager (`secrets`), SSM SecureString (`parameters`), and SSM String (`string_parameters`) |

### Cross-module wiring pattern

The typical wiring order when composing modules in a root config:

1. `iam` → produces `role_arn` fed into `lambda`
2. `lambda` → produces `invoke_arn` fed into `api_gateway`, `function_arn` fed into `cognito`
3. `api_gateway` → produces `execution_arn` fed back into `lambda` (`api_gateway_execution_arn`)
4. `cognito` → produces `user_pool_id`, `client_id` fed into `secrets` or Lambda env vars

### Secrets module sensitivity

The `secrets` and `parameters` variables are marked `sensitive = true`. Use `nonsensitive()` carefully — the module already wraps `for_each` keys with it. Avoid printing secret outputs.

### DynamoDB GSI / LSI

The `dynamodb` module does not expose GSI or LSI variables. Add them directly in the module or extend `variables.tf` before use.
