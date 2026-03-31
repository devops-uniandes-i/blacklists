TFVARS := terraform.tfvars
TF     := terraform

.PHONY: help init infra-create infra-destroy plan

help:
	@echo "Comandos disponibles:"
	@echo "  make init           Inicializa Terraform y descarga el provider AWS"
	@echo "  make infra-create   Crea toda la infraestructura RDS en AWS"
	@echo "  make infra-destroy  Destruye toda la infraestructura RDS en AWS"
	@echo "  make plan           Muestra el plan sin aplicar cambios"

init:
	@test -f $(TFVARS) || (echo "ERROR: Crea terraform.tfvars primero (copia terraform.tfvars.example)" && exit 1)
	$(TF) init

plan: init
	$(TF) plan -var-file="$(TFVARS)"

infra-create: init
	$(TF) apply -var-file="$(TFVARS)" -auto-approve

infra-destroy: init
	$(TF) destroy -var-file="$(TFVARS)" -auto-approve
