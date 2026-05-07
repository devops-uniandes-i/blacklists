TFVARS  := terraform.tfvars
TF      := terraform
VERSION := $(shell date +%Y%m%d%H%M%S)

.PHONY: help init plan infra-create infra-destroy \
        deploy-all-at-once deploy-rolling deploy-rolling-additional deploy-immutable

help:
	@echo ""
	@echo "=== Infraestructura ==="
	@echo "  make init                     Inicializa Terraform y descarga providers"
	@echo "  make plan                     Muestra el plan sin aplicar cambios"
	@echo "  make infra-create             Crea toda la infraestructura (VPC + RDS + EB) con AllAtOnce"
	@echo "  make infra-destroy            Destruye toda la infraestructura"
	@echo ""
	@echo "=== Estrategias de Despliegue ==="
	@echo "  make deploy-all-at-once       Despliega en todas las instancias simultaneamente"
	@echo "  make deploy-rolling           Despliega de a 1 instancia (capacidad reducida)"
	@echo "  make deploy-rolling-additional Despliega con instancia adicional (capacidad completa)"
	@echo "  make deploy-immutable         Crea nuevas instancias antes de reemplazar"
	@echo ""
	@echo "  Opcional: VERSION=v2 make deploy-rolling  (fuerza nueva version)"
	@echo ""

init:
	@test -f $(TFVARS) || (echo "ERROR: Crea terraform.tfvars primero (copia terraform.tfvars.example)" && exit 1)
	$(TF) init

plan: init
	$(TF) plan -var-file="$(TFVARS)"

infra-create: init
	$(TF) apply -var-file="$(TFVARS)" -auto-approve

infra-destroy: init
	$(TF) destroy -var-file="$(TFVARS)" -auto-approve

# ── Estrategias de Despliegue ─────────────────────────────────────────────────
# Cada comando usa un VERSION distinto para forzar que Beanstalk reconozca
# una nueva application version y ejecute el despliegue con la estrategia dada.

deploy-all-at-once: init
	@echo ">>> Estrategia: All-at-once | Version: $(VERSION)"
	$(TF) apply -var-file="$(TFVARS)" \
	  -var="deployment_policy=AllAtOnce" \
	  -var="app_version=$(VERSION)" \
	  -auto-approve

deploy-rolling: init
	@echo ">>> Estrategia: Rolling (batch=1) | Version: $(VERSION)"
	$(TF) apply -var-file="$(TFVARS)" \
	  -var="deployment_policy=Rolling" \
	  -var="batch_size=1" \
	  -var="app_version=$(VERSION)" \
	  -auto-approve

deploy-rolling-additional: init
	@echo ">>> Estrategia: Rolling with Additional Batch (batch=1) | Version: $(VERSION)"
	$(TF) apply -var-file="$(TFVARS)" \
	  -var="deployment_policy=RollingWithAdditionalBatch" \
	  -var="batch_size=1" \
	  -var="app_version=$(VERSION)" \
	  -auto-approve

deploy-immutable: init
	@echo ">>> Estrategia: Immutable | Version: $(VERSION)"
	$(TF) apply -var-file="$(TFVARS)" \
	  -var="deployment_policy=Immutable" \
	  -var="app_version=$(VERSION)" \
	  -auto-approve
