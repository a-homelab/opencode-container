# opencode-container

Reusable OpenCode v2 authoring image with Git, GitHub CLI, Python, uv, Bash, curl,
jq, ripgrep, OpenSSL and common file/text utilities installed at build time.
Deployment-specific configuration, skills, instructions and credentials belong
in mounted configuration and Secrets.

## Image construction

The build and runtime stages each start from `debian:stable-slim`. The build
stage installs Python, CA certificates and archive tools to prepare OpenCode
and the Python toolkit. uv comes from `ghcr.io/astral-sh/uv:0.12.17`. Image
references use readable tags. Builds support `linux/amd64` and `linux/arm64`.
`UV_VERSION` is a build argument, defaulting to `0.12.17`.

OpenCode 2.0.11 is downloaded as a standalone glibc binary from the official
`@opencode/cli-linux-x64-baseline` or `@opencode/cli-linux-arm64` package. Docker
selects the matching download stage using `TARGETARCH`. Dockerfile
`ADD` downloads the versioned archive over HTTPS.
The AMD64 build uses the baseline binary for broader CPU compatibility. No
upstream OpenCode image, Node.js runtime or npm installation is involved.

The [Dockerfile](Dockerfile) lists the Debian runtime tools inline. The fresh
runtime stage installs them and their dependencies with APT using
`--no-install-recommends`, including Bash, `/bin/sh`, CA certificates and timezone
data. It then copies in the OpenCode binary, uv and the prebuilt Python toolkit.
Build-stage downloads and package lists stay behind; only the runtime stage
cleans up its APT lists because those layers ship in the final image.

APT and dpkg remain in the image. The non-root user and read-only root filesystem
prevent changes to system packages at runtime. uv manages Python environments
and optional one-off dependencies in writable state storage.

Base tags and Debian packages can change between builds. Use `--pull --no-cache`
to refresh them, test the result and publish the image. Deployment
references use readable version tags as well.

## Shared Python toolkit

[`toolkit/pyproject.toml`](toolkit/pyproject.toml) and
[`toolkit/uv.lock`](toolkit/uv.lock) seed the same package set and exact pins as
Ben's `~/.agents/toolkit`. This repo owns its copy; builds do not read a user's
home directory. `uv sync --locked` builds `/opt/agent-toolkit/.venv` with Debian's
Python during the image build, including `ruff` and `pytest`.

Run a skill or scratch script from any working directory:

```sh
uv run --project /opt/agent-toolkit --no-sync python /path/to/script.py
uv run --project /opt/agent-toolkit --no-sync ruff check /path/to/script.py
uv run --project /opt/agent-toolkit --no-sync pytest /workspace/tests
```

The toolkit includes requests, httpx, tenacity, pydantic, pyyaml, pandas,
beautifulsoup4, lxml, python-dateutil, rich, jinja2 and python-dotenv. These
packages are ready to import without network access or runtime installation.
The project, lockfile and environment are root-owned and remain read-only at
runtime; `--no-sync` skips environment updates. Python helper processes for Git
credentials and health checks still use standard-library-only `python3`.

For an occasional extra dependency, use a separate uv overlay:

```sh
uv run --project /opt/agent-toolkit --no-sync --with boto3 python /path/to/script.py
```

This requires package-index access on a cache miss. Use an exact `--with`
version when the task needs repeatability. Do not use `--with` for packages
already in the toolkit. The writable cache is `/state/cache/uv`; overlays do
not modify the shared environment. Automatic Python downloads are disabled,
and uv uses the installed interpreter. These defaults do not prevent an agent
from installing other packages into its writable workspace.

For a permanent dependency change, run `uv add --project toolkit <package>`
in this repository, review both files, rebuild and publish the image.
Keep skill source and purpose prompts in the deployment's read-only ConfigMaps.
The image supplies the shared Python runtime and its tools guide.

## Runtime contract

- Default user and group: `65532:65532` (`opencode`).
- Working directory: `/workspace`.
- HOME and XDG directories: `/state` and its subdirectories.
- Default command: `opencode serve --hostname 0.0.0.0 --port 4096`.
- Writable mounts: `/state`, `/workspace`, and `/tmp`.
- API authentication: supply `OPENCODE_PASSWORD` at runtime.

Use a read-only root filesystem, drop capabilities and disable privilege
escalation. A Kubernetes `fsGroup: 65532` gives the processes access to mounted
PVCs. The image contains no GitHub App, token renewer, repository list, Mi Casa
purpose prompt or skills. Mount those separately. The Helm chart
also disables OpenCode self-updates and project configuration overrides.

Provider integrations may need additional language runtimes or libraries. Add
reviewed dependencies here, rebuild, and update the deployment's image reference.
Small skill scripts can stay in read-only ConfigMaps. This image does not bundle
an image-generation integration or assume access to any model provider.

## Tools guide and custom purpose

[`config/AGENTS.md`](config/AGENTS.md) is baked into the image at
`/opt/opencode-defaults/AGENTS.md`. `OPENCODE_CONFIG_DIR` selects this read-only
global directory, so OpenCode loads the tools guide automatically. It documents
installed commands, writable paths, Git/gh and the prebuilt uv toolkit.

Mount a separate configuration file and set `OPENCODE_CONFIG` to its path.
Use native v2 agent settings to supply the agent's purpose, for example:

```json
{
  "agents": {
    "build": {
      "system": "{file:/opt/agent-purpose/purpose.md}"
    }
  }
}
```

Mount `purpose.md` read-only alongside that configuration. Custom named agents
can also set `agents.<name>.system` and `default_agent`. OpenCode combines the
selected agent's system prompt with the global tools guide. Keep
`OPENCODE_CONFIG_DIR` at its image default to retain that guide; replacing the
global directory replaces its instruction source. The v2 `instructions` array
does not currently load files, so it is not used for this integration.

The Helm chart maps `opencode.instructions` to the default build agent's system
prompt using its mounted file. Skills continue to come from the deployment's
configured skill directories.

## Build and verify

```sh
docker build --pull --platform linux/amd64 -t opencode-container:test .
docker run --rm opencode-container:test --version
```

Override versions with `--build-arg UV_VERSION=<version>` and
`--build-arg OPENCODE_VERSION=<version>`.
For a local ARM64 build, use `--platform linux/arm64` on an ARM64 machine or a
builder with ARM64 emulation.

The smoke checks live directly in [the image workflow](.github/workflows/ci.yaml).
After publishing, its smoke job starts the AMD64 image as a service with a
read-only root filesystem, no capabilities and writable temporary mounts.
Steps check the non-root identity, installed tools, offline Python toolkit,
local Git commits/worktrees, API version and authentication. The API version
and binary must match the image's OCI version label. No remote Git writes or
model provider credentials are needed.

## Publish and consume

Every push to `main` calls the full reusable workflow
`a-homelab/github-actions/.github/workflows/build-push-container.yaml@main`
to build, scan and publish AMD64 and ARM64 images. A dependent smoke job tests
the published image through GitHub Actions `services`. A failed smoke job marks
the workflow failed; the image has already been published at that point.
Each build publishes two tags, for example:

- `2.0.11`: the latest container build for that OpenCode version.
- `2.0.11-abc1234`: that OpenCode version plus the first seven characters of
  the opencode-container commit SHA.

The smoke job pulls the commit-specific tag. Runs remain serialized so the
shared version tag is published in sequence.

Set `OPENCODE_VERSION` in the workflow's `image-tags` job and `UV_VERSION` in
the reusable workflow's `build-args` input. The OpenCode build argument and both
tags derive from the same version. The OCI version label remains the upstream
OpenCode version. Dockerfile defaults also support local builds.

Bump these values in Git and push to `main` to publish. Updating a deployment
remains a separate GitOps operation. Use a published commit-specific tag with
`IfNotPresent` to select the build explicitly:

```yaml
components:
  main:
    container:
      image:
        repository: ghcr.io/a-homelab/opencode-container
        tag: 2.0.11-abc1234
        pullPolicy: IfNotPresent
```

Replace the example SHA with the published build's tag. The plain `2.0.11`
tag still moves between builds and should use `Always`. Re-running CI for the
same commit can replace its commit-specific tag too; use a digest if strict
artifact immutability is required. Set package visibility or deployment pull
credentials as appropriate.

The Helm chart remains sourced from Git. Its runtime containers reuse this
image; no startup tools installer or tools volume is required. Publishing the
image does not deploy it or change GitHub repository permissions.

Sources: [OpenCode v2 installation](https://opencode.ai/v2/docs),
[official v2 installer](https://opencode.ai/v2/install),
[Debian image](https://hub.docker.com/_/debian),
[uv in Docker](https://docs.astral.sh/uv/guides/integration/docker/).

Instruction loading: [OpenCode v2 instructions](https://opencode.ai/v2/docs/instructions).
