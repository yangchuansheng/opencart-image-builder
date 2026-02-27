# OpenCart Image Builder

Build and publish OpenCart Docker images from upstream source tags.

## What this repository does

- Manually trigger a GitHub Actions workflow.
- Choose upstream source repository and tag at trigger time.
- Build an Apache + PHP OpenCart runtime image.
- Push image to `ghcr.io/<your-owner>/<image_name>`.

## Workflow inputs

- `source_repo`: upstream repository, default `opencart/opencart`
- `source_tag`: required tag to build, e.g. `4.1.0.3` or `v4.1.0.3`
- `image_name`: image name under your GHCR namespace, default `opencart`
- `push_latest`: whether to also tag/push `latest`

## Image tags generated

- `<source_tag>` (raw)
- `<source_tag without v prefix>`
- `sha-<commit>`
- `latest` (only when `push_latest=true`)

## Runtime environment variables

- `OPENCART_AUTO_INSTALL` (default `false`)
- `OPENCART_REMOVE_INSTALLER` (default `false`)
- `OPENCART_USERNAME` (default `admin`)
- `OPENCART_PASSWORD` (default `admin`)
- `OPENCART_ADMIN_EMAIL` (default `admin@example.com`)
- `OPENCART_HTTP_SERVER` (default `http://localhost/`)
- `DB_DRIVER` (default `mysqli`)
- `DB_HOSTNAME` (default `mysql`)
- `DB_USERNAME` (default `opencart`)
- `DB_PASSWORD` (default `opencart`)
- `DB_DATABASE` (default `opencart`)
- `DB_PORT` (default `3306`)
- `DB_PREFIX` (default `oc_`)

## Notes

- Workflow pushes to GHCR using `GITHUB_TOKEN`, no extra secret is required for GHCR.
- The selected `source_tag` must exist in the upstream repository.
