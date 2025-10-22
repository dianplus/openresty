# OpenResty for DianPlus

## Differences from upstream OpenResty alpine Dockerfile

- Upstream reference: `https://github.com/openresty/docker-openresty/blob/master/alpine/Dockerfile`
- Parameterized paths and layout: Configurable install prefix and module/config/log/run directories, adopting `/etc/openresty` structure for better system integration.
- User and permissions: Creates `openresty` user and group with proper log directory ownership for minimal privilege operation.
- Package sources and networking: Switches Alpine repository to Aliyun mirror for better network stability in China.
- Lua runtime components: Additional runtime dependencies `lua-sec` and `lua-socket` for enhanced scripting capabilities.
- Third-party modules: Integrates Tengine's `dyups` dynamic upstream module into the build process.
- Configuration layout: Places default virtual host configuration in `/etc/openresty/conf.d/` to align with overall structure.
- Port exposure: Explicitly exposes ports 80 and 443 for container orchestration and local development.

## Automated Build

This project uses GitHub Actions for automated builds, supporting both AMD64 and ARM64 architectures:

### Build Triggers

- **Automatic**: Push to `develop`/`master` branches or create `v*` tags
- **Manual**: Run workflows manually through GitHub Actions page

### Image Access

After build completion, images are pushed to GitHub Container Registry:

- **AMD64 Image**: `ghcr.io/dianplus/openresty`
- **ARM64 Image**: `ghcr.io/dianplus/openresty` (with `-arm64` suffix)

### Tag Strategy

- `develop` branch → `develop`, `develop-<sha>`
- `master` branch → `latest`, `latest-<sha>`
- Version tags → `v1.0.0`, `v1.0.0-<sha>`

### Performance Advantages

- **Native Build**: Uses Aliyun spot instances, both AMD64 and ARM64 are native architectures
- **Fast Build**: Build time 15-20 minutes
- **Ultra Low Cost**: Single build cost approximately ¥0.05-0.1
- **Auto Cleanup**: Instances destroyed immediately after build completion

For detailed configuration, please refer to [GitHub Workflows Documentation](.github/workflows/README.md).
