# Blacklist Service — Infraestructura con Terraform

Este directorio contiene la infraestructura como código (IaC) para desplegar la base de datos PostgreSQL del servicio Blacklist en **AWS RDS**, junto con la red privada que la rodea.

## Arquitectura

```
AWS Region (us-east-1)
└── VPC  10.0.0.0/16
    ├── Public Subnet AZ-a  10.0.10.0/24   ← aplicación / bastion
    ├── Public Subnet AZ-b  10.0.11.0/24
    ├── Private Subnet AZ-a 10.0.1.0/24    ← RDS (no internet)
    └── Private Subnet AZ-b 10.0.2.0/24    ← RDS (subnet group)
```

**Recursos creados:**

| Recurso | Descripción |
|---|---|
| `aws_vpc` | VPC dedicada con DNS habilitado |
| `aws_internet_gateway` | Acceso a Internet para subnets públicas |
| `aws_subnet` (public ×2) | Subnets para capa de aplicación |
| `aws_subnet` (private ×2) | Subnets aisladas para RDS (multi-AZ ready) |
| `aws_route_table` | Tabla de rutas públicas con ruta 0.0.0.0/0 → IGW |
| `aws_security_group` (app) | SG de la aplicación — puede conectar a RDS |
| `aws_security_group` (rds) | SG de RDS — sólo acepta tráfico del app SG en :5432 |
| `aws_db_subnet_group` | Agrupa las dos subnets privadas para RDS |
| `aws_db_parameter_group` | Parámetros PostgreSQL 16 (log_connections activado) |
| `aws_db_instance` | RDS PostgreSQL 16, almacenamiento gp3 cifrado |

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
# editar terraform.tfvars con tu db_password

make infra-create   # crea toda la infraestructura
make infra-destroy  # destruye toda la infraestructura
make plan           # previsualiza cambios sin aplicar
make init           # solo inicializa Terraform
```

---

## Pasos de despliegue

### 2. Crear el archivo de variables

```bash
cp terraform.tfvars.example terraform.tfvars
```

Editar `terraform.tfvars` con los valores reales. Los campos obligatorios son:

```hcl
db_password = "MiPasswordSeguro123!"   # mínimo 8 caracteres
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

| Variable | Descripción | Default |
|---|---|---|
| `aws_region` | Región de AWS | `us-east-1` |
| `project_name` | Prefijo para todos los recursos | `blacklist` |
| `environment` | Entorno (dev/staging/prod) | `dev` |
| `vpc_cidr` | CIDR del VPC | `10.0.0.0/16` |
| `private_subnet_cidrs` | CIDRs de subnets privadas (RDS) | `["10.0.1.0/24", "10.0.2.0/24"]` |
| `public_subnet_cidrs` | CIDRs de subnets públicas | `["10.0.10.0/24", "10.0.11.0/24"]` |
| `db_name` | Nombre de la base de datos | `blacklistdb` |
| `db_username` | Usuario maestro de RDS | `postgres` |
| `db_password` | Contraseña maestra de RDS | *requerido* |
| `db_instance_class` | Tipo de instancia RDS | `db.t3.micro` |
| `db_allocated_storage` | Almacenamiento en GB | `20` |
| `db_engine_version` | Versión de PostgreSQL | `16.3` |
| `db_multi_az` | Alta disponibilidad Multi-AZ | `false` |
| `db_deletion_protection` | Protección contra eliminación | `false` |
| `db_skip_final_snapshot` | Omitir snapshot final al destruir | `true` |
| `db_backup_retention_period` | Días de retención de backups | `7` |
| `allowed_cidr_blocks` | CIDRs con acceso directo a RDS | `[]` |

---

## Estructura de archivos

```
terraform/
├── providers.tf              # Configuración del provider AWS
├── variables.tf              # Declaración de variables
├── main.tf                   # Recursos: VPC, subnets, SGs, RDS
├── outputs.tf                # Valores de salida
├── terraform.tfvars.example  # Plantilla de variables (sin secretos)
└── README.md                 # Esta documentación
```
