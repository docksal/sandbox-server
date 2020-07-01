# Default project variables.
include project.env
# Project-specific overrides. These should be version controlled.
PROJECT_OVERRIDES:=project-override.env
# Untracked local overrides file, for development purposes.
LOCAL_OVERRIDES:=local-override.env
DOCKER_ENV_FILE:=--env-file=project.env
# GCLOUD:=docker run -it --rm --volumes-from gcloud-config -v `pwd`:/opt/deployment $(DOCKER_ENV_FILE) google/cloud-sdk:$(CLOUD_SDK_IMAGE_VERSION) gcloud

ifneq ("$(wildcard $(PROJECT_OVERRIDES))","")
    include $(PROJECT_OVERRIDES)
	DOCKER_ENV_FILE+=--env-file=$(PROJECT_OVERRIDES)
endif

ifneq ("$(wildcard $(LOCAL_OVERRIDES))","")
	include $(LOCAL_OVERRIDES)
	DOCKER_ENV_FILE+=--env-file=$(LOCAL_OVERRIDES)
endif

GCLOUD:=docker run -it --rm \
	--volumes-from gcloud-config \
	-v `pwd`:/opt/deployment \
	$(DOCKER_ENV_FILE) \
	google/cloud-sdk:$(CLOUD_SDK_IMAGE_VERSION) \
	gcloud

export

login:
	docker run -ti --name gcloud-config google/cloud-sdk:$(CLOUD_SDK_IMAGE_VERSION) gcloud auth login

guard-%:
	@ if [ "${${*}}" = "" ]; then \
		echo "Environment variable $* not set"; \
		exit 1; \
	fi

bash:
	docker run -it --rm \
	--volumes-from gcloud-config \
	-v `pwd`:/opt/deployment \
	$(DOCKER_ENV_FILE) \
	-w /opt/deployment \
	google/cloud-sdk:$(CLOUD_SDK_IMAGE_VERSION) /bin/bash

clean-container:
	docker rm -v gcloud-config

create:
	$(GCLOUD) deployment-manager deployments create $(DISK_DEPLOYMENT) \
		--template=/opt/deployment/templates/docksal_disk.jinja \
		--properties="diskSizeGb:$(DISK_SIZE),zone:'$(ZONE)'"

	$(GCLOUD) deployment-manager deployments create $(TEMPLATE_DEPLOYMENT) \
		--template=/opt/deployment/templates/docksal_template.jinja \
		--properties="templateId:'$(TEMPLATE_ID)',region:'$(REGION)',machineType:'$(DEFAULT_MACHINE_SIZE)',preemptive:$(PREEMPTIVE),docksalVersion:'$(DOCKSAL_VERSION)'"

	$(GCLOUD) deployment-manager deployments create $(GROUP_DEPLOYMENT) \
		--template=/opt/deployment/templates/docksal_group.py \
		--properties="templateId:'$(TEMPLATE_ID)',zone:'$(ZONE)'"

update:
	$(GCLOUD) deployment-manager deployments update $(DISK_DEPLOYMENT) \
		--template=/opt/deployment/templates/docksal_disk.jinja \
		--properties="diskSizeGb:$(DISK_SIZE)"

	$(GCLOUD) deployment-manager deployments update $(TEMPLATE_DEPLOYMENT) \
		--template=/opt/deployment/templates/docksal_template.jinja \
		--properties="templateId:'$(TEMPLATE_ID)',region:'$(REGION)',machineType:'$(DEFAULT_MACHINE_SIZE)',preemptive:$(PREEMPTIVE),docksalVersion:'$(DOCKSAL_VERSION)'" \
		--delete-policy=abandon

	$(GCLOUD) deployment-manager deployments update $(GROUP_DEPLOYMENT) \
		--template=/opt/deployment/templates/docksal_group.py \
		--properties="templateId:'$(TEMPLATE_ID)',zone:'$(ZONE)'"

	$(GCLOUD) compute instance-groups managed rolling-action start-update $(GROUP_NAME) \
		--version template=$(TEMPLATE_ID) \
		--zone $(ZONE)

delete:
	$(GCLOUD) deployment-manager deployments delete $(GROUP_DEPLOYMENT) --quiet

	$(GCLOUD) deployment-manager deployments delete $(TEMPLATE_DEPLOYMENT) --quiet

	$(GCLOUD) deployment-manager deployments delete $(DISK_DEPLOYMENT) --quiet
