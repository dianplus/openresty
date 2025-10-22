# GitHub Workflows

## Docker Build Workflows

### 1. AMD64 Cloud Instance Build Workflow

**File**: `auto-amd64-build.yml`

#### AMD64 Features

- Uses Aliyun spot instances to create AMD64 cloud instances on-demand
- Native AMD64 build with excellent performance
- Automatic cleanup of cloud instances after build completion
- Ultra low cost (single build approximately ¥0.05-0.1)

#### AMD64 Trigger Methods

- **Automatic**: develop/master branch push, v* tags
- **Manual**: Supports custom image tags

#### AMD64 Tag Strategy (with architecture suffix)

- develop: `develop-amd64`, `develop-amd64-<sha>`
- master: `latest-amd64`, `latest-amd64-<sha>`
- tags: `v1.0.0-amd64`, `v1.0.0-amd64-<sha>`

### 2. ARM64 Cloud Instance Build Workflow

**File**: `auto-arm64-build.yml`

#### ARM64 Features

- Uses Aliyun spot instances to create ARM64 cloud instances on-demand
- Native ARM64 build with excellent performance
- Automatic cleanup of cloud instances after build completion
- Ultra low cost (single build approximately ¥0.05-0.1)

#### ARM64 Trigger Methods

- **Automatic**: develop/master branch push, v* tags
- **Manual**: Supports custom image tags

#### ARM64 Tag Strategy (with architecture suffix)

- develop: `develop-arm64`, `develop-arm64-<sha>`
- master: `latest-arm64`, `latest-arm64-<sha>`
- tags: `v1.0.0-arm64`, `v1.0.0-arm64-<sha>`

### 3. Cloud Instance Management Tool

**File**: `aliyun-spot-runner.yml`

#### Features

- Manually create/delete Aliyun spot instances
- View running instances
- Manage self-hosted runners

#### Usage

1. Select "Aliyun Spot Runner Manager (Multi-Arch)" workflow
2. Choose operation:
   - `create` - Create instance (supports AMD64/ARM64)
   - `destroy` - Delete instance
   - `list` - List instances
3. Configure parameters:
   - `architecture` - Target architecture (arm64/amd64)
   - `instance_type` - Instance type (supports dynamic selection, no preset required)
   - `image_id` - Image ID
   - `runner_name` - Runner name prefix

### Image Access and Merge

After build completion, images are pushed to GitHub Container Registry:

- **AMD64 Image**: `ghcr.io/dianplus/openresty:<tag>-amd64`
- **ARM64 Image**: `ghcr.io/dianplus/openresty:<tag>-arm64`

Multi-architecture merged available: `ghcr.io/dianplus/openresty:<tag>` (manifest points to amd64 and arm64)

### Performance Advantages

- **Native Build**: Uses corresponding architecture cloud instances, avoiding emulator performance loss
- **Fast Build**: Both AMD64/ARM64 build time 15-20 minutes
- **Ultra Low Cost**: Single build cost approximately ¥0.05-0.1
- **Auto Cleanup**: Instances destroyed immediately after build completion, avoiding cost accumulation

### Configuration Requirements

#### GitHub Secrets

- `ALIYUN_ACCESS_KEY_ID` - Aliyun Access Key ID
- `ALIYUN_ACCESS_KEY_SECRET` - Aliyun Access Key Secret
- `ALIYUN_SECURITY_GROUP_ID` - Security Group ID
- `ALIYUN_VSWITCH_ID` - Primary VSwitch ID (fallback use, recommend pre-building VSwitches for multiple zones)
- `ALIYUN_ARM64_IMAGE_ID` - ARM64 Image ID
- `ALIYUN_AMD64_IMAGE_ID` - AMD64 Image ID

#### Permission Requirements

- `contents: read` - Read repository content
- `packages: write` - Push images to GitHub Container Registry
- `actions: write` - Manage self-hosted runners

### Usage Examples

#### Test Build (no push)

```yaml
image_tag: test-build
push_image: false
```

#### Release Custom Version

```yaml
image_tag: v1.0.0-custom
push_image: true
```

#### Create Instance

**Create ARM64 Instance (dynamic instance type)**:

```yaml
action: create
architecture: arm64
instance_type: auto  # Dynamically selected by spot-instance-advisor
runner_name: my-arm64-runner
```

**Create AMD64 Instance (dynamic instance type)**:

```yaml
action: create
architecture: amd64
instance_type: auto  # Dynamically selected by spot-instance-advisor
runner_name: my-amd64-runner
```

#### Instance Selection Strategy

- Dynamically query and select optimal instance types using [`spot-instance-advisor`](https://github.com/maskshell/spot-instance-advisor)
- AMD64: CPU:RAM = 1:1, specification range 8c8g–64c64g (no instance family restriction)
- ARM64: CPU:RAM = 1:2, specification range 8c16g–64c128g (limited to `ecs.c8y,ecs.c8r`)

Zone strategy: Priority use advisor recommended zone → Dynamic query zones supporting the instance type → Preset zone fallback.
