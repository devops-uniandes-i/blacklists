# Blacklist Service — Infraestructura con Terraform

Este directorio contiene la infraestructura como código (IaC) para desplegar el servicio Blacklist en **AWS Elastic Beanstalk** con base de datos **AWS RDS PostgreSQL**, junto con la red privada que los rodea.

## Arquitectura

```
Internet (port 80)
    ↓
ALB (Application Load Balancer) [subnets públicas]
    ↓
EC2 t3.micro × 3–6 instancias [Auto Scaling, managed by EB]
  └── Docker container (Flask API, puerto 3012)
  └── nginx proxy (80 → 3012)
    ↓
RDS PostgreSQL 16 [subnets privadas, sin acceso a Internet]
```

```
AWS Region (us-east-1)
└── VPC  10.0.0.0/16
    ├── Public Subnet AZ-a  10.0.10.0/24   ← ALB + EC2 (Beanstalk)
    ├── Public Subnet AZ-b  10.0.11.0/24   ← ALB + EC2 (Beanstalk)
    ├── Private Subnet AZ-a 10.0.1.0/24    ← RDS (no internet)
    └── Private Subnet AZ-b 10.0.2.0/24    ← RDS (subnet group)
```

**Recursos creados:**

| Recurso | Descripción |
|---|---|
| `aws_vpc` | VPC dedicada con DNS habilitado |
| `aws_internet_gateway` | Acceso a Internet para subnets públicas |
| `aws_subnet` (public ×2) | Subnets para ALB y EC2 de Beanstalk |
| `aws_subnet` (private ×2) | Subnets aisladas para RDS (multi-AZ ready) |
| `aws_route_table` | Tabla de rutas públicas con ruta 0.0.0.0/0 → IGW |
| `aws_security_group` (alb) | SG del ALB — acepta HTTP :80 desde Internet |
| `aws_security_group` (app) | SG de las EC2 — acepta :80 solo desde el ALB |
| `aws_security_group` (rds) | SG de RDS — acepta :5432 solo desde las EC2 |
| `aws_db_subnet_group` | Agrupa las dos subnets privadas para RDS |
| `aws_db_parameter_group` | Parámetros PostgreSQL 16 (log_connections activado) |
| `aws_db_instance` | RDS PostgreSQL 16, almacenamiento gp3 cifrado |
| `aws_iam_role` (service) | Role del servicio Elastic Beanstalk |
| `aws_iam_role` (ec2) | Role de las instancias EC2 de Beanstalk |
| `aws_iam_instance_profile` | Instance profile asociado al role EC2 |
| `aws_s3_bucket` | Bucket para guardar los bundles de la aplicación |
| `aws_elastic_beanstalk_application` | Aplicación Beanstalk |
| `aws_elastic_beanstalk_application_version` | Versión de la app (ZIP en S3) |
| `aws_elastic_beanstalk_environment` | Environment con ALB, Auto Scaling y Docker |

---

## Requisitos previos

| Herramienta | Versión mínima |
|---|---|
| [Terraform](https://developer.hashicorp.com/terraform/install) | 1.5.0 |
| [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) | 2.x |
| Cuenta AWS con permisos sobre EC2/VPC y RDS | — |

### 1. Configurar credenciales AWS

```bash
# Opción A — perfil nombrado (recomendado)
aws configure --profile blacklist-dev
# AWS Access Key ID: AKIA...
# AWS Secret Access Key: ...
# Default region name: us-east-1

export AWS_PROFILE=blacklist-dev

# Opción B — variables de entorno
export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_DEFAULT_REGION="us-east-1"
```

Verificar acceso:

```bash
aws sts get-caller-identity
```

Salida esperada:
```json
{
    "UserId": "AIDA...",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/mi-usuario"
}
```

---

## Comandos Make (forma rápida)

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# editar terraform.tfvars con tus secrets

make infra-create              # crea toda la infraestructura (All-at-once)
make deploy-all-at-once        # redespliegue con All-at-once
make deploy-rolling            # redespliegue con Rolling (1 instancia a la vez)
make deploy-rolling-additional # redespliegue con Rolling + instancia adicional
make deploy-immutable          # redespliegue con instancias completamente nuevas
make infra-destroy             # destruye toda la infraestructura
make plan                      # previsualiza cambios sin aplicar
make init                      # solo inicializa Terraform
```

---

## Workflow de despliegue con 4 estrategias

Este es el flujo completo para documentar las 4 estrategias de despliegue en AWS Elastic Beanstalk.

### Paso 0 — Configurar credenciales y variables

```bash
# Credenciales AWS
export AWS_PROFILE=tu-perfil
# o
export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_DEFAULT_REGION="us-east-1"

# Variables de la infraestructura
cp terraform.tfvars.example terraform.tfvars
# Editar terraform.tfvars: db_password, jwt_secret_key, auth_password
```

### Paso 1 — Inicializar Terraform

```bash
make init
```

### Paso 2 — Estrategia 1: All-at-once

Despliega en **todas las instancias simultáneamente**. El más rápido, con un breve período de inactividad durante el reemplazo.

```bash
make infra-create
# Crea VPC + RDS + Beanstalk environment con 3 instancias usando All-at-once
```

Al finalizar, Terraform imprime el output `beanstalk_url`. Verificar:

```bash
curl http://<beanstalk_url>/health
# → "pong"
```

**Qué documentar:**
- Instancias: 3 (todas actualizadas a la vez)
- Tiempo total: ver pestaña **Events** en la consola de EB
- Instancias: las mismas (no se crean nuevas)

### Paso 3 — Estrategia 2: Rolling

Despliega de **1 instancia a la vez**. Sin downtime total, pero con capacidad reducida (2 de 3) durante el despliegue.

```bash
make deploy-rolling
```

**Qué observar en la consola de EB → Events:**
- Cada instancia se actualiza secuencialmente
- En EC2 → Auto Scaling Group, 2 instancias sirven tráfico mientras 1 se actualiza

**Qué documentar:**
- Instancias: 3 originales (rolling sobre las mismas)
- Batch size: 1 instancia a la vez
- Sin downtime total, capacidad reducida transitoriamente

### Paso 4 — Estrategia 3: Rolling with Additional Batch

Igual que Rolling pero **agrega 1 instancia extra** durante el despliegue para mantener la capacidad completa (3 activas siempre).

```bash
make deploy-rolling-additional
```

**Qué observar:**
- Momentáneamente habrá **4 instancias** (3 originales + 1 extra nueva)
- Al completar el rolling, la instancia extra se termina

**Qué documentar:**
- Instancias en pico: 4 (3 originales + 1 batch adicional)
- Sin reducción de capacidad en ningún momento

### Paso 5 — Estrategia 4: Immutable

Crea un **Auto Scaling Group completamente nuevo** con instancias nuevas. Solo hace el swap cuando todas están saludables. Rollback más seguro.

```bash
make deploy-immutable
```

**Qué observar:**
- En EC2 → Auto Scaling Groups, aparece un segundo ASG temporal con 3 instancias nuevas
- Cuando todas están `Ok`, se hace el swap y el ASG viejo se termina

**Qué documentar:**
- Instancias: 3 nuevas (no se tocan las originales hasta el swap)
- Despliegue más lento pero rollback instantáneo si falla

### Paso 6 — Destruir la infraestructura

```bash
make infra-destroy
```

> **Advertencia:** elimina todos los recursos incluyendo la base de datos.

---

## Verificar el despliegue

### Health check de la API

```bash
# Reemplazar <URL> con el valor del output beanstalk_url
curl http://<URL>/health
# → "pong"
```

### Obtener token y probar la API

```bash
# 1. Obtener JWT
TOKEN=$(curl -s -X POST http://<URL>/auth/token \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin"}' | jq -r '.access_token')

# 2. Agregar email a la lista negra
curl -X POST http://<URL>/blacklists \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","app_uuid":"550e8400-e29b-41d4-a716-446655440000"}'

# 3. Consultar si un email está bloqueado
curl -H "Authorization: Bearer $TOKEN" \
  "http://<URL>/blacklists?email=test@example.com"
```

### Ver el estado del environment con AWS CLI

```bash
aws elasticbeanstalk describe-environments \
  --environment-names blacklist-dev-env \
  --query "Environments[0].{Status:Status,Health:Health,URL:CNAME}" \
  --output table

# Ver eventos del último despliegue
aws elasticbeanstalk describe-events \
  --environment-name blacklist-dev-env \
  --max-records 20 \
  --output table
```

### Consultar outputs en cualquier momento

```bash
terraform output beanstalk_url
terraform output beanstalk_deployment_policy
terraform output beanstalk_app_version
```

---

## Pasos de despliegue

### 2. Crear el archivo de variables

```bash
cp terraform.tfvars.example terraform.tfvars
```

Editar `terraform.tfvars` con los valores reales. Los campos obligatorios son:

```hcl
db_password    = "MiPasswordSeguro123!"          # mínimo 8 caracteres
jwt_secret_key = "clave-secreta-muy-larga-aleatoria"
auth_password  = "MiPasswordAdmin123!"
```

> **Nunca** commitees `terraform.tfvars` al repositorio — está en `.gitignore`.

### 3. Inicializar Terraform

Descarga el provider de AWS y prepara el directorio de trabajo:

```bash
terraform init
```

Salida esperada:
```
Terraform has been successfully initialized!
```

### 4. Revisar el plan de ejecución

Muestra todos los recursos que se van a crear **sin aplicar cambios**:

```bash
terraform plan -var-file="terraform.tfvars"
```

Revisar que el plan incluya los recursos esperados (VPC, subnets, SGs, RDS).

### 5. Aplicar la infraestructura

```bash
terraform apply -var-file="terraform.tfvars"
```

Terraform mostrará el plan y pedirá confirmación. Escribir `yes` para continuar.

El proceso tarda aproximadamente **5–10 minutos** (la creación de RDS es el paso más largo).

Al finalizar, se imprimen los outputs:

```
Outputs:

database_url        = "postgresql://postgres:****@blacklist-dev-postgres.xxxx.us-east-1.rds.amazonaws.com:5432/blacklistdb"
rds_endpoint        = "blacklist-dev-postgres.xxxx.us-east-1.rds.amazonaws.com:5432"
rds_host            = "blacklist-dev-postgres.xxxx.us-east-1.rds.amazonaws.com"
rds_port            = 5432
rds_db_name         = "blacklistdb"
rds_instance_id     = "blacklist-dev-postgres"
vpc_id              = "vpc-0abc..."
...
```

---

## Verificar que la infraestructura funciona

### Verificar el estado de RDS con AWS CLI

```bash
# Estado general de la instancia (debe ser "available")
aws rds describe-db-instances \
  --db-instance-identifier blacklist-dev-postgres \
  --query "DBInstances[0].DBInstanceStatus" \
  --output text

# Endpoint de conexión
aws rds describe-db-instances \
  --db-instance-identifier blacklist-dev-postgres \
  --query "DBInstances[0].Endpoint" \
  --output json
```

### Verificar recursos de red

```bash
# Listar subnets creadas
aws ec2 describe-subnets \
  --filters "Name=tag:Project,Values=blacklist" \
  --query "Subnets[*].{ID:SubnetId,CIDR:CidrBlock,AZ:AvailabilityZone,Public:MapPublicIpOnLaunch}" \
  --output table

# Listar security groups
aws ec2 describe-security-groups \
  --filters "Name=tag:Project,Values=blacklist" \
  --query "SecurityGroups[*].{ID:GroupId,Name:GroupName}" \
  --output table
```

### Probar conectividad a RDS (desde instancia en la VPC)

Desde una instancia EC2 en la subnet pública (o a través de un bastion):

```bash
# Instalar cliente PostgreSQL si no está disponible
sudo apt-get install -y postgresql-client   # Ubuntu/Debian
# o
sudo yum install -y postgresql              # Amazon Linux

# Conectar a la base de datos
psql -h <rds_host> -U postgres -d blacklistdb -p 5432

# Verificar la conexión con un query simple
SELECT version();
```

### Consultar outputs en cualquier momento

```bash
terraform output
terraform output rds_endpoint
terraform output rds_host
```

### Configurar la aplicación Flask

Exportar la variable de entorno con el endpoint de RDS:

```bash
RDS_HOST=$(terraform output -raw rds_host)
export DATABASE_URL="postgresql://postgres:<password>@${RDS_HOST}:5432/blacklistdb"
```

---

## Gestión del estado

### Ver el estado actual

```bash
terraform show
terraform state list
```

### Refrescar el estado desde AWS

```bash
terraform refresh -var-file="terraform.tfvars"
```

---

## Destruir la infraestructura

> Advertencia: esto elimina **todos** los recursos incluida la base de datos.

```bash
terraform destroy -var-file="terraform.tfvars"
```

---

## Variables de configuración

### Red y entorno

| Variable | Descripción | Default |
|---|---|---|
| `aws_region` | Región de AWS | `us-east-1` |
| `project_name` | Prefijo para todos los recursos | `blacklist` |
| `environment` | Entorno (dev/staging/prod) | `dev` |
| `vpc_cidr` | CIDR del VPC | `10.0.0.0/16` |
| `private_subnet_cidrs` | CIDRs de subnets privadas (RDS) | `["10.0.1.0/24", "10.0.2.0/24"]` |
| `public_subnet_cidrs` | CIDRs de subnets públicas | `["10.0.10.0/24", "10.0.11.0/24"]` |

### RDS

| Variable | Descripción | Default |
|---|---|---|
| `db_name` | Nombre de la base de datos | `blacklistdb` |
| `db_username` | Usuario maestro de RDS | `postgres` |
| `db_password` | Contraseña maestra de RDS | *requerido* |
| `db_instance_class` | Tipo de instancia RDS | `db.t3.micro` |
| `db_allocated_storage` | Almacenamiento en GB | `20` |
| `db_engine_version` | Versión de PostgreSQL | `16.3` |
| `db_multi_az` | Alta disponibilidad Multi-AZ | `false` |
| `db_deletion_protection` | Protección contra eliminación | `false` |
| `db_skip_final_snapshot` | Omitir snapshot final al destruir | `true` |
| `db_backup_retention_period` | Días de retención de backups | `0` |
| `allowed_cidr_blocks` | CIDRs con acceso directo a RDS | `[]` |

### Elastic Beanstalk

| Variable | Descripción | Default |
|---|---|---|
| `eb_instance_type` | Tipo de instancia EC2 | `t3.micro` |
| `eb_min_instances` | Mínimo de instancias en el ASG | `3` |
| `eb_max_instances` | Máximo de instancias en el ASG | `6` |
| `deployment_policy` | Estrategia de despliegue | `AllAtOnce` |
| `batch_size_type` | Tipo de batch: `Fixed` o `Percentage` | `Fixed` |
| `batch_size` | Número de instancias por batch (Rolling) | `1` |
| `app_version` | Etiqueta de versión — cambiar para disparar deploy | `v1` |

### Secrets de la aplicación

| Variable | Descripción | Default |
|---|---|---|
| `jwt_secret_key` | Clave para firmar JWT | *requerido* |
| `auth_username` | Usuario para `POST /auth/token` | `admin` |
| `auth_password` | Contraseña para `POST /auth/token` | *requerido* |

---

## Estrategias de despliegue

| Estrategia | `deployment_policy` | Instancias afectadas | Capacidad durante deploy | Downtime |
|---|---|---|---|---|
| All-at-once | `AllAtOnce` | Todas a la vez | Reducida (0%) | Sí (breve) |
| Rolling | `Rolling` | 1 a la vez (batch=1) | Reducida (66%) | No |
| Rolling + Batch | `RollingWithAdditionalBatch` | 1 extra + rotate | Completa (100%) | No |
| Immutable | `Immutable` | Nuevas instancias | Completa (100%) | No |

---

## Estructura de archivos

```
terraform/
├── providers.tf              # Providers AWS, random, archive
├── variables.tf              # Declaración de variables
├── main.tf                   # VPC, subnets, security groups, RDS
├── iam.tf                    # IAM roles e instance profile para EB
├── s3.tf                     # Bucket S3 y bundle ZIP de la aplicación
├── beanstalk.tf              # Elastic Beanstalk application y environment
├── outputs.tf                # Valores de salida (URL de EB, RDS endpoint, etc.)
├── terraform.tfvars.example  # Plantilla de variables (sin secretos)
├── terraform.tfvars          # Variables reales (git-ignored)
└── README.md                 # Esta documentación
```
