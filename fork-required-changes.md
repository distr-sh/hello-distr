# Fork Required Changes

This fork needs a few changes from the upstream `distr-sh/hello-distr` defaults before releases can build, publish, and deploy through Distr. The README gets you most of the way, but not all the way. Check the diff from this branch to upstream for full details. This doc provides a summary.

## Why These Changes Exist

The upstream repository publishes artifacts under upstream-owned locations, especially `ghcr.io/distr-sh/...` and `oci://ghcr.io/distr-sh/...`. Those paths work for the upstream repo because its GitHub Actions token has permission to write to the `distr-sh` packages.

This fork publishes from `subconscious-systems/hello-distr`, and the deployment artifacts are intended to live in the Distr registry namespace shown in the Distr UI:

```text
registry.distr.sh/subconscious/...
```

That means the fork should use Distr Registry as the artifact source of truth rather than GHCR.

## Registry Changes

Container images should be pushed to:

```text
registry.distr.sh/subconscious/hello-distr/backend
registry.distr.sh/subconscious/hello-distr/frontend
registry.distr.sh/subconscious/hello-distr/proxy
registry.distr.sh/subconscious/hello-distr/jobs
```

The Helm chart should be pushed to:

```text
oci://registry.distr.sh/subconscious/charts
```

The Kubernetes Distr version should reference:

```text
oci://registry.distr.sh/subconscious/charts/hello-distr
```

The Docker Compose file, Helm values, vulnerability scanning script, and Zarf package should all consume images from `registry.distr.sh/subconscious/hello-distr/...`.

## Do Not Push `latest`

The Distr registry rejected a release push with:

```text
unsupported: this tag already exists and cannot be overwritten
```

The failing tag was `latest`.

This is because `docker/metadata-action` can emit `latest` automatically for semver tag builds. That worked against GHCR because GHCR allows mutable tags by default. Distr Registry appears to treat tags as immutable, at least in this namespace.

For this release flow, `latest` is not needed. Release Please updates the deployment artifacts to use versioned tags like `0.5.4`, so the workflow should disable automatic `latest` generation:

```yaml
flavor: |
  latest=false
```

This keeps releases immutable and avoids trying to overwrite an existing `latest` tag.

## API Base

The upstream demo workflow used the demo Distr API:

```text
https://demo.distr.sh/api/v1
```

This fork should use the production Distr API:

```text
https://app.distr.sh/api/v1
```

Both Docker and Kubernetes `distr-create-version-action` jobs need this value.

## Required GitHub Secrets And Variables

In the fork repository, configure:

Secrets:

```text
DISTR_TOKEN
RELEASE_GITHUB_TOKEN
```

Variables:

```text
DISTR_APPLICATION_ID
HELLO_DISTR_HELM_APPLICATION_ID
```

`DISTR_TOKEN` is used both to push artifacts to `registry.distr.sh` and to create versions in Distr.

`RELEASE_GITHUB_TOKEN` is used by Release Please to create release PRs and tags.

`DISTR_APPLICATION_ID` should point to the Docker-type Distr application.

`HELLO_DISTR_HELM_APPLICATION_ID` should point to the Kubernetes-type Distr application.

## PMIG Matrix Entry

The upstream workflow had a second Docker deployment matrix entry:

```yaml
- DISTR_TOKEN_SECRET: DISTR_TOKEN_PMIG
  DISTR_APPLICATION_ID_VAR: DISTR_APPLICATION_ID_PMIG
```

Repo history suggests `PMIG` was tied to the original upstream author/user `pmig` and a second personal or test Distr deployment target. It is not documented as a product requirement.

For this fork, remove that matrix entry unless there is intentionally a second Docker Distr app to update.

Keeping it without defining `DISTR_TOKEN_PMIG` causes:

```text
Input api-token is required
```

## Zarf Package

Zarf is optional for normal Docker and Helm Distr deployments. It is useful for packaging a Kubernetes deployment for air-gapped or restricted environments.

If the `build-zarf` job stays enabled, the Zarf chart definition needs an explicit chart version:

```yaml
charts:
  - name: hello-distr
    namespace: hello-distr
    version: "###ZARF_PKG_TMPL_VERSION###"
    localPath: ../charts/hello-distr
```

Without that, Zarf fails with:

```text
invalid chart definition: chart "hello-distr" must include a chart version
```

If Zarf packaging is not needed, the `build-zarf` job can be disabled or removed.