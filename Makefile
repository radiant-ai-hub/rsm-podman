# Makefile for rsm-msba-k8s Docker and rsm-podman multi-platform builds

# =============================================================================
# Docker Configuration (Docker Hub)
# =============================================================================
DOCKER_IMAGE := vnijs/rsm-msba-k8s
DOCKER_FILE := docker-k8s/Dockerfile
DOCKER_BUILDER := multiplatform-builder

# =============================================================================
# Podman Configuration (GHCR)
# =============================================================================
PODMAN_IMAGE := ghcr.io/radiant-ai-hub/rsm-podman
CONTAINERFILE := rsm-podman/Containerfile

# =============================================================================
# Shared Configuration
# =============================================================================
PLATFORMS := linux/amd64,linux/arm64
VERSION ?= latest

# Legacy alias for backwards compatibility
IMAGE_NAME := $(DOCKER_IMAGE)
DOCKERFILE := $(DOCKER_FILE)
BUILDER_NAME := $(DOCKER_BUILDER)

# Detect current platform
CURRENT_PLATFORM := $(shell uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')

# Colors for output
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
NC := \033[0m # No Color

.PHONY: help
help: ## Show this help message
	@echo "$(GREEN)Multi-Platform Build System$(NC)"
	@echo "$(YELLOW)Docker:$(NC) $(DOCKER_IMAGE) -> Docker Hub"
	@echo "$(YELLOW)Podman:$(NC) $(PODMAN_IMAGE) -> GHCR"
	@echo ""
	@echo "$(YELLOW)Usage:$(NC)"
	@echo "  make [target] [VERSION=x.x.x]"
	@echo ""
	@echo "$(YELLOW)Available targets:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(YELLOW)Docker Examples:$(NC)"
	@echo "  make build               # Build and push Docker image to Docker Hub"
	@echo "  make test                # Build local Docker test image"
	@echo ""
	@echo "$(YELLOW)Podman Examples:$(NC)"
	@echo "  make podman-build        # Build and push Podman image to GHCR"
	@echo "  make podman-test         # Build local Podman test image"
	@echo ""

.PHONY: check-docker
check-docker: ## Check if Docker is running and buildx is available
	@echo "$(GREEN)Checking Docker setup...$(NC)"
	@docker info > /dev/null 2>&1 || (echo "$(RED)Error: Docker is not running$(NC)" && exit 1)
	@docker buildx version > /dev/null 2>&1 || (echo "$(RED)Error: Docker buildx is not available$(NC)" && exit 1)
	@echo "$(GREEN)✓ Docker and buildx are available$(NC)"

.PHONY: setup-builder
setup-builder: check-docker ## Setup buildx multi-platform builder
	@echo "$(GREEN)Setting up buildx builder...$(NC)"
	@if ! docker buildx ls | grep -q "$(BUILDER_NAME)"; then \
		echo "$(YELLOW)Creating new builder: $(BUILDER_NAME)$(NC)"; \
		docker buildx create --name $(BUILDER_NAME) --driver docker-container --use; \
	else \
		echo "$(GREEN)Using existing builder: $(BUILDER_NAME)$(NC)"; \
		docker buildx use $(BUILDER_NAME); \
	fi
	@echo "$(GREEN)Bootstrapping builder...$(NC)"
	@docker buildx inspect --bootstrap

.PHONY: login
login: ## Login to Docker Hub (uses DOCKER_TOKEN or prompts for credentials)
	@echo "$(GREEN)Logging in to Docker Hub...$(NC)"
	@if [ -n "$$DOCKER_TOKEN" ]; then \
		echo "$(GREEN)Using DOCKER_TOKEN environment variable$(NC)"; \
		echo "$$DOCKER_TOKEN" | docker login --username vnijs --password-stdin; \
	elif [ -n "$$DOCKER_PASSWORD" ] && [ -n "$$DOCKER_USERNAME" ]; then \
		echo "$(GREEN)Using DOCKER_USERNAME and DOCKER_PASSWORD$(NC)"; \
		echo "$$DOCKER_PASSWORD" | docker login --username "$$DOCKER_USERNAME" --password-stdin; \
	else \
		echo "$(YELLOW)No credentials found in environment, running interactive login$(NC)"; \
		docker login; \
	fi

.PHONY: test-auth
test-auth: ## Test Docker Hub authentication
	@echo "$(GREEN)Testing Docker Hub authentication...$(NC)"
	@docker manifest inspect $(IMAGE_NAME):latest > /dev/null 2>&1 && \
		echo "$(GREEN)✓ Authentication working - you have access to $(IMAGE_NAME)$(NC)" || \
		echo "$(YELLOW)⚠ Cannot access repository - login may be required$(NC)"

.PHONY: test
test: setup-builder ## Build local test image for current platform (no push)
	@echo "$(GREEN)Building test image for linux/$(CURRENT_PLATFORM)...$(NC)"
	@mkdir -p build-logs
	@docker buildx build \
		--platform linux/$(CURRENT_PLATFORM) \
		--tag $(IMAGE_NAME):latest \
		--build-arg IMAGE_VERSION=test \
		--load \
		--progress=plain \
		-f $(DOCKERFILE) \
		. 2>&1 | tee build-logs/latest_$$(date +%Y%m%d_%H%M%S).log
	@echo "$(GREEN)✓ Test build complete: $(IMAGE_NAME):latest$(NC)"

.PHONY: validate
validate: ## Validate environment variables in built image
	@echo "$(GREEN)Validating image: $(IMAGE_NAME):latest$(NC)"
	@./scripts/validate-image.sh $(IMAGE_NAME):latest

.PHONY: test-validate
test-validate: test validate ## Build local test image and validate environment

.PHONY: build
build: setup-builder test-auth ## Build and push multi-platform image
	@echo "$(GREEN)Building multi-platform image: $(IMAGE_NAME):$(VERSION)$(NC)"
	@echo "$(YELLOW)Platforms: $(PLATFORMS)$(NC)"
	@echo "$(YELLOW)This may take 30-60 minutes...$(NC)"
	@mkdir -p build-logs
	@docker buildx build \
		--platform $(PLATFORMS) \
		--tag $(IMAGE_NAME):$(VERSION) \
		--tag $(IMAGE_NAME):latest \
		--build-arg IMAGE_VERSION=$(VERSION) \
		--push \
		--progress=plain \
		-f $(DOCKERFILE) \
		. 2>&1 | tee build-logs/multiplatform-build_$$(date +%Y%m%d_%H%M%S).log
	@echo "$(GREEN)✓ Build complete and pushed to Docker Hub$(NC)"
	@echo "$(GREEN)Image: $(IMAGE_NAME):$(VERSION)$(NC)"
	@docker buildx imagetools inspect $(IMAGE_NAME):$(VERSION)

.PHONY: build-no-cache
build-no-cache: setup-builder test-auth ## Build and push multi-platform image without cache
	@echo "$(GREEN)Building multi-platform image without cache: $(IMAGE_NAME):$(VERSION)$(NC)"
	@echo "$(YELLOW)Platforms: $(PLATFORMS)$(NC)"
	@echo "$(YELLOW)This may take 30-60 minutes...$(NC)"
	@mkdir -p build-logs
	@docker buildx build \
		--platform $(PLATFORMS) \
		--tag $(IMAGE_NAME):$(VERSION) \
		--tag $(IMAGE_NAME):latest \
		--build-arg IMAGE_VERSION=$(VERSION) \
		--no-cache \
		--push \
		--progress=plain \
		-f $(DOCKERFILE) \
		. 2>&1 | tee build-logs/multiplatform-build_$$(date +%Y%m%d_%H%M%S).log
	@echo "$(GREEN)✓ Build complete and pushed to Docker Hub$(NC)"
	@echo "$(GREEN)Image: $(IMAGE_NAME):$(VERSION)$(NC)"
	@docker buildx imagetools inspect $(IMAGE_NAME):$(VERSION)

.PHONY: inspect
inspect: ## Inspect the multi-platform manifest for a version
	@echo "$(GREEN)Inspecting $(IMAGE_NAME):$(VERSION)$(NC)"
	@docker buildx imagetools inspect $(IMAGE_NAME):$(VERSION)

.PHONY: clean-builder
clean-builder: ## Remove the buildx builder
	@echo "$(YELLOW)Removing buildx builder: $(BUILDER_NAME)$(NC)"
	@docker buildx rm $(BUILDER_NAME) || true
	@echo "$(GREEN)✓ Builder removed$(NC)"

.PHONY: clean-logs
clean-logs: ## Clean up build log files
	@echo "$(YELLOW)Cleaning build logs...$(NC)"
	@rm -rf build-logs/*
	@echo "$(GREEN)✓ Logs cleaned$(NC)"

.PHONY: clean-test-images
clean-test-images: ## Remove local test images
	@echo "$(YELLOW)Removing test images...$(NC)"
	@docker rmi $(IMAGE_NAME):latest 2>/dev/null || true
	@echo "$(GREEN)✓ Test images removed$(NC)"

.PHONY: clean
clean: clean-test-images clean-logs ## Clean up test images and logs

.PHONY: status
status: ## Show current build environment status
	@echo "$(GREEN)Build Environment Status$(NC)"
	@echo "$(YELLOW)========================$(NC)"
	@echo "Image Name:       $(IMAGE_NAME)"
	@echo "Version:          $(VERSION)"
	@echo "Platforms:        $(PLATFORMS)"
	@echo "Current Platform: linux/$(CURRENT_PLATFORM)"
	@echo "Dockerfile:       $(DOCKERFILE)"
	@echo ""
	@echo "$(YELLOW)Docker Status:$(NC)"
	@docker info | grep -E "Operating System|OSType|Architecture" || true
	@echo ""
	@echo "$(YELLOW)Buildx Builders:$(NC)"
	@docker buildx ls || echo "$(RED)buildx not available$(NC)"
	@echo ""
	@echo "$(YELLOW)Authentication:$(NC)"
	@docker info 2>/dev/null | grep "Username:" || echo "Not logged in"

# =============================================================================
# Podman Targets (GHCR)
# =============================================================================

.PHONY: check-podman
check-podman: ## Check if Podman is available
	@echo "$(GREEN)Checking Podman setup...$(NC)"
	@podman --version > /dev/null 2>&1 || (echo "$(RED)Error: Podman is not installed$(NC)" && exit 1)
	@echo "$(GREEN)✓ Podman is available$(NC)"

.PHONY: podman-login
podman-login: check-podman ## Login to GHCR (uses gh auth token or prompts)
	@echo "$(GREEN)Logging in to GHCR...$(NC)"
	@if command -v gh >/dev/null 2>&1; then \
		echo "$(GREEN)Using gh auth token$(NC)"; \
		unset GH_TOKEN && gh auth token | podman login ghcr.io --username vnijs --password-stdin; \
	elif [ -f ~/.env ]; then \
		GH_TOKEN=$$(grep "^GH_TOKEN=" ~/.env | cut -d'"' -f2); \
		if [ -n "$$GH_TOKEN" ]; then \
			echo "$(GREEN)Using GH_TOKEN from ~/.env$(NC)"; \
			echo "$$GH_TOKEN" | podman login ghcr.io --username vnijs --password-stdin; \
		else \
			echo "$(YELLOW)No GH_TOKEN in ~/.env, running interactive login$(NC)"; \
			podman login ghcr.io; \
		fi; \
	else \
		echo "$(YELLOW)Running interactive login$(NC)"; \
		podman login ghcr.io; \
	fi

.PHONY: podman-test
podman-test: check-podman ## Build local Podman test image for current platform (no push)
	@echo "$(GREEN)Building Podman test image for linux/$(CURRENT_PLATFORM)...$(NC)"
	@mkdir -p build-logs
	@podman build \
		--platform linux/$(CURRENT_PLATFORM) \
		--tag $(PODMAN_IMAGE):test \
		--build-arg IMAGE_VERSION=test \
		--format docker \
		-f $(CONTAINERFILE) \
		. 2>&1 | tee build-logs/podman-test_$$(date +%Y%m%d_%H%M%S).log
	@echo "$(GREEN)✓ Podman test build complete: $(PODMAN_IMAGE):test$(NC)"

.PHONY: podman-validate
podman-validate: ## Validate environment variables in Podman image
	@echo "$(GREEN)Validating Podman image: $(PODMAN_IMAGE):test$(NC)"
	@./scripts/validate-image.sh $(PODMAN_IMAGE):test podman

.PHONY: podman-test-validate
podman-test-validate: podman-test podman-validate ## Build local Podman test image and validate

.PHONY: podman-build
podman-build: check-podman podman-login ## Build and push multi-platform Podman image to GHCR
	@echo "$(GREEN)Building multi-platform Podman image: $(PODMAN_IMAGE):$(VERSION)$(NC)"
	@echo "$(YELLOW)Platforms: $(PLATFORMS)$(NC)"
	@echo "$(YELLOW)This may take 30-60 minutes...$(NC)"
	@mkdir -p build-logs
	@# Clean up any existing manifest/image with this name
	@podman manifest rm $(PODMAN_IMAGE):$(VERSION) 2>/dev/null || true
	@podman rmi $(PODMAN_IMAGE):$(VERSION) 2>/dev/null || true
	@# Create fresh manifest
	@podman manifest create $(PODMAN_IMAGE):$(VERSION)
	@# Build for each platform and add to manifest
	@for platform in $$(echo $(PLATFORMS) | tr ',' ' '); do \
		echo "$(GREEN)Building for $$platform...$(NC)"; \
		podman build \
			--platform $$platform \
			--tag $(PODMAN_IMAGE):$(VERSION)-$$(echo $$platform | tr '/' '-') \
			--build-arg IMAGE_VERSION=$(VERSION) \
			--format docker \
			-f $(CONTAINERFILE) \
			. 2>&1 | tee -a build-logs/podman-build_$$(date +%Y%m%d_%H%M%S).log; \
		podman manifest add $(PODMAN_IMAGE):$(VERSION) $(PODMAN_IMAGE):$(VERSION)-$$(echo $$platform | tr '/' '-'); \
	done
	@# Push manifest to GHCR
	@echo "$(GREEN)Pushing manifest to GHCR...$(NC)"
	@podman manifest push --all $(PODMAN_IMAGE):$(VERSION) docker://$(PODMAN_IMAGE):$(VERSION)
	@podman manifest push --all $(PODMAN_IMAGE):$(VERSION) docker://$(PODMAN_IMAGE):latest
	@echo "$(GREEN)✓ Build complete and pushed to GHCR$(NC)"
	@echo "$(GREEN)Image: $(PODMAN_IMAGE):$(VERSION)$(NC)"

.PHONY: podman-build-no-cache
podman-build-no-cache: check-podman podman-login ## Build and push multi-platform Podman image without cache
	@echo "$(GREEN)Building multi-platform Podman image without cache: $(PODMAN_IMAGE):$(VERSION)$(NC)"
	@echo "$(YELLOW)Platforms: $(PLATFORMS)$(NC)"
	@mkdir -p build-logs
	@# Clean up any existing manifest/image with this name
	@podman manifest rm $(PODMAN_IMAGE):$(VERSION) 2>/dev/null || true
	@podman rmi $(PODMAN_IMAGE):$(VERSION) 2>/dev/null || true
	@# Create fresh manifest
	@podman manifest create $(PODMAN_IMAGE):$(VERSION)
	@for platform in $$(echo $(PLATFORMS) | tr ',' ' '); do \
		echo "$(GREEN)Building for $$platform (no cache)...$(NC)"; \
		podman build \
			--platform $$platform \
			--tag $(PODMAN_IMAGE):$(VERSION)-$$(echo $$platform | tr '/' '-') \
			--build-arg IMAGE_VERSION=$(VERSION) \
			--no-cache \
			--format docker \
			-f $(CONTAINERFILE) \
			. 2>&1 | tee -a build-logs/podman-build-nocache_$$(date +%Y%m%d_%H%M%S).log; \
		podman manifest add $(PODMAN_IMAGE):$(VERSION) $(PODMAN_IMAGE):$(VERSION)-$$(echo $$platform | tr '/' '-'); \
	done
	@podman manifest push --all $(PODMAN_IMAGE):$(VERSION) docker://$(PODMAN_IMAGE):$(VERSION)
	@podman manifest push --all $(PODMAN_IMAGE):$(VERSION) docker://$(PODMAN_IMAGE):latest
	@echo "$(GREEN)✓ Build complete and pushed to GHCR$(NC)"

.PHONY: podman-inspect
podman-inspect: ## Inspect the multi-platform manifest for Podman image
	@echo "$(GREEN)Inspecting $(PODMAN_IMAGE):$(VERSION)$(NC)"
	@podman manifest inspect $(PODMAN_IMAGE):$(VERSION) || skopeo inspect --raw docker://$(PODMAN_IMAGE):$(VERSION)

.PHONY: podman-clean
podman-clean: ## Clean up local Podman test images
	@echo "$(YELLOW)Removing Podman test images...$(NC)"
	@podman rmi $(PODMAN_IMAGE):test 2>/dev/null || true
	@podman rmi $(PODMAN_IMAGE):$(VERSION) 2>/dev/null || true
	@echo "$(GREEN)✓ Podman test images removed$(NC)"

.PHONY: podman-status
podman-status: ## Show Podman build environment status
	@echo "$(GREEN)Podman Build Environment Status$(NC)"
	@echo "$(YELLOW)================================$(NC)"
	@echo "Image Name:       $(PODMAN_IMAGE)"
	@echo "Version:          $(VERSION)"
	@echo "Platforms:        $(PLATFORMS)"
	@echo "Current Platform: linux/$(CURRENT_PLATFORM)"
	@echo "Containerfile:    $(CONTAINERFILE)"
	@echo ""
	@echo "$(YELLOW)Podman Version:$(NC)"
	@podman --version || echo "$(RED)Podman not installed$(NC)"
	@echo ""
	@echo "$(YELLOW)GHCR Authentication:$(NC)"
	@podman login --get-login ghcr.io 2>/dev/null || echo "Not logged in to GHCR"
