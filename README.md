# OpenResty for DianPlus

A multi-architecture container image build system using GitHub Actions and Alibaba Cloud Spot instances for cost-effective, high-performance automated builds.

## Overview

This project provides an automated build pipeline for multi-architecture (AMD64/ARM64) container images using:

- **GitHub Actions** for CI/CD orchestration
- **Alibaba Cloud Spot Instances** for ultra-low-cost native architecture builds
- **Self-hosted Runners** for build execution
- **Custom image management** for optimized runner base images

The root `Dockerfile` is a customized OpenResty image based on the upstream [OpenResty Dockerfile](https://github.com/openresty/docker-openresty/blob/master/alpine/Dockerfile).

## Key Features

### Multi-Architecture Support

- Native AMD64 and ARM64 builds (no QEMU emulation overhead)
- Automatic architecture-specific image tagging
- Multi-arch manifest merging for unified tags

### Cost Optimization

- **Ultra-low cost**: ~¥0.05-0.1 per build using Spot instances
- **Automatic cleanup**: Instances self-destruct after build completion
- **Dynamic instance selection**: Automatically selects optimal instance types based on pricing

### Custom Image Management

- Automated custom image building for runner base images
- Image family support (`ALIYUN_IMAGE_FAMILY`) for automatic latest image retrieval
- Intelligent image cleanup: keeps `-latest` suffix for new images, renames old images with date suffix
- Configurable image retention (default: 5 images per prefix)

### Advanced Instance Management

- Dynamic VSwitch selection based on availability zone
- Disk category fallback strategy (cloud_essd → cloud_ssd → cloud_efficiency)
- Instance tagging for resource tracking
- Self-destruct mechanism with fallback cleanup

## Workflows

### 1. Build AMD64 (`build-amd64.yml`)

Builds AMD64 architecture images on native AMD64 Spot instances.

**Features:**

- Dynamic spot instance selection
- Self-hosted runner auto-configuration
- Automatic instance cleanup
- Architecture-specific tagging (`<tag>-amd64`)

### 2. Build ARM64 (`build-arm64.yml`)

Builds ARM64 architecture images on native ARM64 Spot instances.

**Features:**

- Same as AMD64 workflow but for ARM64 architecture
- Architecture-specific tagging (`<tag>-arm64`)

### 3. Build Custom Images (`build-custom-images.yml`)

Builds and manages custom Ubuntu 24 base images for self-hosted runners.

**Features:**

- Automated custom image creation from spot instances
- Image family support for automatic base image selection
- Dynamic system disk sizing based on image size
- Image cleanup with date-suffix renaming
- Support for both AMD64 and ARM64 architectures

**Trigger:**

- Scheduled: Daily at 02:00 UTC (10:00 Beijing time)
- Manual: Workflow dispatch with optional force build

### 4. Merge Multi-Arch Manifests (`merge-manifests.yml`)

Merges AMD64 and ARM64 images into unified multi-architecture manifests.

**Features:**

- Creates unified tags (e.g., `latest`, `v1.0.0`)
- Docker automatically selects correct architecture at runtime
- On-demand merging (manual trigger)

## Build Process

### Phase 1: Architecture-Specific Image Build

1. **Trigger Build**
   - Manual workflow dispatch (primary method)
   - Auto-triggers (push/tags) currently disabled - see [Iteration 7](ITERATION_PLAN.md#迭代-7自动触发构建-) in iteration plan

2. **Instance Creation**
   - Dynamic spot instance selection using `spot-instance-advisor`
   - Optimal instance type selection based on pricing
   - Automatic VSwitch selection by availability zone
   - Self-hosted runner configuration (Ephemeral mode)

3. **Build Execution**
   - Native architecture build (no emulation)
   - Push to GitHub Container Registry
   - Architecture-specific tagging: `<tag>-amd64` or `<tag>-arm64`

4. **Cleanup**
   - Instance self-destruct script (primary mechanism)
   - Workflow cleanup job (fallback verification)
   - Zero cost accumulation

### Phase 2: Multi-Architecture Manifest Merge

1. **Trigger Merge**
   - Manual workflow dispatch after both AMD64 and ARM64 builds complete
   - Input target tag (without architecture suffix, e.g., `latest` or `v1.0.0`)
   - Auto-trigger on build completion currently disabled - see [Iteration 9](ITERATION_PLAN.md#迭代-9多架构合并自动化-) in iteration plan

2. **Merge Execution**
   - Verify architecture-specific images exist (`<tag>-amd64` and `<tag>-arm64`)
   - Create and push multi-arch manifest (`<tag>`)
   - Docker automatically selects correct architecture at runtime

## Custom Image Building

The custom image building workflow creates optimized Ubuntu 24 base images for self-hosted runners with pre-installed tools.

### Image Management Features

- **Image Family Support**: Uses `ALIYUN_IMAGE_FAMILY` environment variable to automatically retrieve the latest base image
- **Dynamic Size Calculation**: Automatically queries image size (in GB) and sets system disk size accordingly
- **Intelligent Cleanup**:
  - New images always keep `-latest` suffix
  - Old images renamed with date suffix (e.g., `github-runner-ubuntu24-amd64-202511201200`)
  - Total images (latest + dated) counted and kept within `KEEP_IMAGE_COUNT` limit
- **Version Tracking**: Uses version hash to detect existing images and skip rebuilds

### Image Naming Convention

- **Latest image**: `<prefix>-<arch>-latest` (e.g., `github-runner-ubuntu24-amd64-latest`)
- **Historical images**: `<prefix>-<arch>-YYYYMMDDHHMM` (e.g., `github-runner-ubuntu24-amd64-202511201200`)

### Custom Image Configuration

Key environment variables:

- `ALIYUN_IMAGE_FAMILY`: Image family name for automatic base image selection
- `IMAGE_NAME_PREFIX`: Prefix for custom image names (default: `github-runner-ubuntu24`)
- `KEEP_IMAGE_COUNT`: Number of images to retain (default: 5)

## Image Access

Images are pushed to GitHub Container Registry:

- **Multi-arch merged images** (recommended): `ghcr.io/dianplus/openresty:<tag>` - Docker automatically matches platform
- **Architecture-specific images** (for debugging): `ghcr.io/dianplus/openresty:<tag>-amd64` or `ghcr.io/dianplus/openresty:<tag>-arm64`

## Usage Examples

### Building Architecture-Specific Images

**Option 1: Automatic Trigger (Recommended)**

- Push changes to `develop` or `master` branch to automatically trigger both AMD64 and ARM64 builds
- Create a tag with `v*` pattern (e.g., `v1.0.0`) to automatically trigger both AMD64 and ARM64 builds

**Option 2: Manual Trigger**

- Manually trigger `Build AMD64` workflow
- Manually trigger `Build ARM64` workflow
- Wait for both builds to complete

### Merging Multi-Architecture Images

**Option 1: Automatic Trigger (Recommended)**

- After both AMD64 and ARM64 builds complete successfully, the `Merge Multi-Arch Manifests` workflow will automatically run
- The merged manifest will be tagged and pushed automatically based on the source branch or tag

**Option 2: Manual Trigger**

- Navigate to GitHub Actions page
- Find `Merge Multi-Arch Manifests` workflow
- Click "Run workflow"
- Enter target tag (e.g., `latest` or `v1.0.0`)
- Click "Run workflow" to execute merge

### Pulling Images

```bash
# Pull multi-arch image (recommended, Docker auto-matches platform)
docker pull ghcr.io/dianplus/openresty:latest

# Pull architecture-specific image (for debugging)
docker pull ghcr.io/dianplus/openresty:latest-amd64
docker pull ghcr.io/dianplus/openresty:latest-arm64
```

### Querying Custom Images

```bash
# Get image ID by name
export ALIYUN_REGION_ID=cn-hangzhou
export IMAGE_NAME=github-runner-ubuntu24-amd64-latest
python3 .github/scripts/get-image-id-by-name.py
```

## Key Scripts

### Core Build Scripts

- `build-custom-image.py`: Custom image building with comprehensive image management
- `select-instance.py`: Optimal spot instance type selection
- `create-spot-instance.py`: Spot instance creation with retry mechanism

### Runner Management

- `generate-user-data.sh`: User data generation for runner configuration
- `get-registration-token.sh`: Runner registration token retrieval
- `wait-for-runner.sh`: Runner online status monitoring

### Instance Management

- `self-destruct.sh`: Automatic instance termination
- `cleanup-instance.sh`: Fallback cleanup mechanism
- `debug-self-destruct.sh`: Troubleshooting tool

### Image Utilities

- `query-ubuntu-image.py`: Ubuntu image querying
- `get-image-id-by-name.py`: Image ID lookup by name
- `publish-image-to-marketplace.py`: Marketplace publishing

## Configuration

### Required GitHub Variables

- `ALIYUN_REGION_ID`: Alibaba Cloud region ID
- `ALIYUN_VPC_ID`: VPC ID
- `ALIYUN_SECURITY_GROUP_ID`: Security group ID
- `ALIYUN_VSWITCH_ID_*`: VSwitch IDs for each availability zone (A-Z)
- `ALIYUN_AMD64_IMAGE_FAMILY`: Image family for AMD64 base images
- `ALIYUN_ARM64_IMAGE_FAMILY`: Image family for ARM64 base images
- `ALIYUN_KEY_PAIR_NAME`: SSH key pair name
- `ALIYUN_ECS_SELF_DESTRUCT_ROLE_NAME`: RAM role for instance self-destruct

### Optional GitHub Variables

- `IMAGE_NAME_PREFIX`: Custom image name prefix (default: `github-runner-ubuntu24`)
- `KEEP_IMAGE_COUNT`: Number of images to retain (default: 5)
- `IMAGE_BUILD_MIN_CPU`: Minimum CPU cores for image build instances (default: 2)
- `IMAGE_BUILD_MAX_CPU`: Maximum CPU cores for image build instances (default: 8)

### Required GitHub Secrets

- `ALIYUN_ACCESS_KEY_ID`: Alibaba Cloud access key ID
- `ALIYUN_ACCESS_KEY_SECRET`: Alibaba Cloud access key secret
- `GITHUB_TOKEN`: GitHub token for runner registration (with `repo` scope)

## Advantages

- **Native Builds**: AMD64 and ARM64 images built on native architecture instances, no QEMU emulation overhead
- **Ultra-Low Cost**: ~¥0.05-0.1 per build using Spot instances
- **Automatic Cleanup**: Instances self-destruct after build completion
- **Flexible Merging**: On-demand multi-arch manifest merging
- **Intelligent Image Management**: Automatic cleanup and version tracking
- **Dynamic Resource Selection**: Optimal instance and disk type selection

## Documentation

For detailed configuration and requirements, see:

- [Project Overview](requirements/01-overview.md)
- [Workflow Details](requirements/02-workflows.md)
- [Alibaba Cloud Configuration](requirements/03-aliyun-config.md)
- [Runner Setup](requirements/04-runner-setup.md)
- [Network Configuration](requirements/05-network.md)
- [Troubleshooting](requirements/06-troubleshooting-self-destruct.md)
- [Dynamic Instance Selection](requirements/07-dynamic-instance-selection.md)

## License

2-clause BSD License (see [LICENSE](LICENSE) file)
