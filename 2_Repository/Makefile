.PHONY: test validate lint capacity cost local-up demo-deploy demo-rollback demo-scale restore-test new-tenant

test:            ## unit tests for the tooling (runs anywhere with python3 + pyyaml)
	python3 -m unittest discover -s tests -v
validate:        ## tenant schema + EU residency gate
	python3 scripts/validate_tenants.py
lint:            ## needs terraform, helm, kubeconform, tflint (NOT run in the submission sandbox)
	terraform fmt -check -recursive infra/
	for d in infra/provider/aws infra/provider/kind infra/platform infra/modules/tenant; do terraform -chdir=$$d init -backend=false && terraform -chdir=$$d validate; done
	helm lint gitops/charts/app --set image.digest=sha256:$$(printf 'a%.0s' $$(seq 64))
	helm template gitops/charts/app --set image.digest=sha256:$$(printf 'a%.0s' $$(seq 64)) | kubeconform -ignore-missing-schemas -
capacity:
	python3 scripts/capacity.py
cost:
	python3 scripts/cost.py
local-up:
	scripts/local.sh up
demo-deploy:
	scripts/demo-deploy-under-load.sh
demo-rollback:
	scripts/demo-bad-release.sh
demo-scale:
	scripts/demo-scale.sh
restore-test:
	scripts/restore-test.sh
new-tenant:      ## make new-tenant NAME=foo-eu RES=eu SIZE=m RING=ring1-small
	python3 scripts/new_tenant.py --name $(NAME) --residency $(RES) --size $(SIZE) --ring $(RING)

local-down:
	scripts/local.sh down
compose-up:      ## simplest run: docker compose (api + worker + postgres + redis), no Kubernetes
	docker compose up --build -d
compose-down:
	docker compose down -v
jenkins-up:      ## local Jenkins + registry (see docs/HOW-TO-RUN.md part 5)
	docker compose -f jenkins/docker-compose.yml up --build -d
