# Container tools

This image provides the tools below. Follow the configured agent purpose and
repository instructions when deciding how to use them.

## Shell and files

Bash and POSIX sh are installed. Use rg for text searches, find for file
location, jq for JSON, curl for HTTP requests, and rclone for file transfers.
Git, GitHub CLI (gh),
OpenSSL, Python 3, uv, uvx, coreutils, diff, patch, sed, grep, tar and gzip
are on PATH. No Node.js or npm runtime is included.

The process runs as non-root. HOME is /state; use /workspace for repository
checkouts and task outputs, and /tmp for temporary files. Keep installed
binaries, system packages and mounted configuration unchanged. Persistent
storage and credentials are supplied by the deployment.

## Python toolkit

Run Python skills and supporting scripts with the prebuilt environment:

```sh
uv run --project /opt/agent-toolkit --no-sync python /path/to/script.py
uv run --project /opt/agent-toolkit --no-sync ruff check /path/to/script.py
uv run --project /opt/agent-toolkit --no-sync pytest /workspace/tests
```

Already installed: requests, httpx, tenacity, pydantic, pyyaml, pandas,
beautifulsoup4, lxml, python-dateutil, rich, jinja2, python-dotenv, ruff and
pytest. Do not add --with for these packages. They work offline without
installing dependencies or downloading another Python interpreter.

For an additional one-off dependency, use
`uv run --project /opt/agent-toolkit --no-sync --with <package> python script.py`.
This uses a separate environment under the writable uv cache and requires
network access on a cache miss. Do not edit /opt/agent-toolkit or its lockfile.
Permanent tool or dependency changes belong in a reviewed image update.

## Git and GitHub

Use git for local commits, branches, worktrees and remote synchronization.
Use gh for GitHub operations such as inspecting and creating pull requests.
Credentials and write permissions depend on the deployment; installed tools
do not imply authorization. Reuse configured credentials without printing or
copying tokens. Follow the deployment's branch and PR policy.
