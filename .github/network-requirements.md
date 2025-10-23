# Self-hosted Runner Network Requirements

## Overview

Self-hosted runners require specific network connectivity to communicate with GitHub services. This document outlines the network requirements and port configurations needed for successful runner operation.

## Network Connectivity Requirements

### Outbound HTTPS Connections

- **Port 443**: Required for all HTTPS communications with GitHub services
- **Minimum Bandwidth**: 70 kbps upload/download speed
- **Protocol**: HTTPS only (no HTTP)

### Required GitHub Domains

The runner must be able to access the following domains:

#### Core GitHub Services
- `github.com` - Main GitHub service
- `api.github.com` - GitHub API
- `*.actions.githubusercontent.com` - Actions service

#### Actions Downloads
- `codeload.github.com` - Code downloads
- `pkg.actions.githubusercontent.com` - Package downloads

#### Container Registry
- `ghcr.io` - GitHub Container Registry
- `*.pkg.github.com` - GitHub Packages
- `pkg-containers.githubusercontent.com` - Container packages

#### Artifacts and Caching
- `results-receiver.actions.githubusercontent.com` - Results upload
- `*.blob.core.windows.net` - Azure blob storage for artifacts

#### Runner Updates
- `objects.githubusercontent.com` - Object storage
- `objects-origin.githubusercontent.com` - Origin objects
- `github-releases.githubusercontent.com` - Release downloads
- `github-registry-files.githubusercontent.com` - Registry files

#### OIDC and Security
- `*.actions.githubusercontent.com` - OIDC token retrieval

#### Large Files
- `github-cloud.githubusercontent.com` - Cloud storage
- `github-cloud.s3.amazonaws.com` - S3 storage

#### Additional Services
- `dependabot-actions.githubapp.com` - Dependabot
- `release-assets.githubusercontent.com` - Release assets
- `api.snapcraft.io` - Snapcraft API

## Network Configuration

### Firewall Rules

Allow outbound HTTPS (port 443) connections to all required domains:

```bash
# Example iptables rules (adjust as needed)
iptables -A OUTPUT -p tcp --dport 443 -d github.com -j ACCEPT
iptables -A OUTPUT -p tcp --dport 443 -d api.github.com -j ACCEPT
iptables -A OUTPUT -p tcp --dport 443 -d "*.actions.githubusercontent.com" -j ACCEPT
# ... (add rules for all required domains)
```

### Proxy Configuration

If using a corporate proxy, configure the runner with proxy settings:

```bash
# Set proxy environment variables
export HTTP_PROXY=http://proxy.company.com:8080
export HTTPS_PROXY=http://proxy.company.com:8080
export NO_PROXY=localhost,127.0.0.1,.local
```

### DNS Resolution

Ensure proper DNS resolution for all required domains:

```bash
# Test DNS resolution
nslookup github.com
nslookup api.github.com
nslookup actions.githubusercontent.com
```

## Security Considerations

### No Inbound Connections Required

- Self-hosted runners do **NOT** require inbound connections
- All communication is outbound from runner to GitHub
- No need to open inbound ports on the runner

### Network Isolation

- Runners can be placed in private networks
- No public IP addresses required
- Communication through VPC gateway or NAT

## Troubleshooting

### Common Issues

1. **Connection Timeouts**
   - Check firewall rules
   - Verify DNS resolution
   - Test proxy configuration

2. **SSL/TLS Errors**
   - Ensure HTTPS (port 443) is allowed
   - Check certificate validation
   - Verify proxy SSL settings

3. **Authentication Failures**
   - Verify GitHub token permissions
   - Check network connectivity to api.github.com
   - Ensure proper proxy configuration

### Testing Connectivity

```bash
# Test basic connectivity
curl -I https://github.com
curl -I https://api.github.com
curl -I https://actions.githubusercontent.com

# Test with verbose output
curl -v https://api.github.com/user
```

## Aliyun ECS Configuration

### Security Group Rules

For Aliyun ECS instances, configure security group to allow outbound HTTPS:

```bash
# Allow outbound HTTPS
aliyun ecs AuthorizeSecurityGroup \
  --RegionId cn-hangzhou \
  --SecurityGroupId sg-xxx \
  --IpProtocol tcp \
  --PortRange 443/443 \
  --SourceCidrIp 0.0.0.0/0 \
  --Policy accept \
  --NicType internet
```

### VPC Configuration

- Ensure VPC has internet gateway or NAT gateway
- Configure route tables for internet access
- No need for public IP on runner instances

## Cost Optimization

### No Public IP Required

- Self-hosted runners do not need public IP addresses
- Saves ~¥0.02-0.05/hour per instance
- Enhanced security through private networking
- Communication via VPC gateway

### Network Architecture

```
GitHub Actions → Internet → VPC Gateway → Self-hosted Runner (Private IP)
```

This architecture provides:
- Cost savings (no public IP charges)
- Enhanced security (no direct internet access)
- Simplified network management
- Compliance with enterprise security policies
