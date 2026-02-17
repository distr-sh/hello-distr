# hello-distr

This is a web application to demonstrate the build, deployment and release workflow for applications in Distr.
It consists of a Next.js frontend, a Python backend, a job scheduler and a PostgreSQL database.
The containers are deployed via Docker Compose (or Helm for Kubernetes) behind a Caddy reverse proxy,
allowing access to the frontend and the Python API.

Feel free to fork it, tinker around a bit and find out what Distr can offer for your on premises software. 

## Tools

We make use of: 
* GitHub Actions/Workflows
* GitHub Registry (`ghcr.io`)
* [Helm](https://helm.sh/)
* [Release Please](https://github.com/googleapis/release-please-action)
* [`distr-create-version-action`](https://github.com/distr-sh/distr-create-version-action)

## Repository Structure

Apart from a directory for the code, config and `Dockerfile` for each application component (`backend`, `frontend`, `proxy`, `jobs`), 
there are the following deployment specific files/directories:

* `.github/workflows/hello-distr.yaml`: The main CI/CD workflow — builds all services, builds and validates the Helm chart, and pushes versions to Distr.
* `.github/workflows/release-please.yaml`: The Release Please workflow for automated releases.
* `deploy/`: Contains the [production Docker Compose file](deploy/docker-compose.yaml), an [environment template](deploy/env.template), 
  a [Helm chart](deploy/charts/hello-distr/) and [CI scripts](deploy/scripts/) for Helm chart validation.
  These will be uploaded to Distr using the [`distr-create-version-action`](https://github.com/distr-sh/distr-create-version-action), 
  as defined in the [hello-distr workflow](.github/workflows/hello-distr.yaml).
* `release-please-config.json`: Contains the config for the Release Please action.

## How it works

The [hello-distr workflow](.github/workflows/hello-distr.yaml) behaves differently depending on the trigger. 
For example, when opening a PR after or during feature development, 
we want the docker build to run, but of course the built image should not be published or released yet.

All four services (`backend`, `frontend`, `proxy`, `jobs`) are built using a single matrix job (`build`).

### On Pull Request

When opening a PR, the `build` matrix job runs, building each service with Docker. The corresponding
`Dockerfile`s can be found inside each component's directory.

Additionally, the Helm chart is built, linted and validated against multiple Kubernetes versions.

### On Push to main

When pushing to `main`, e.g. by merging a PR, the docker images are built again.

Additionally, the `release-please` workflow is run. For that to work, the corresponding GitHub action needs permissions on the repository.
We set a GitHub secret in this repository and give it the name `RELEASE_GITHUB_TOKEN`. 

For more information about the Release Please token, please [check their docs](https://github.com/googleapis/release-please-action?tab=readme-ov-file#github-credentials).

### On Push Tag (Release)

Once there is at least one commit to `main` since the last release, Release Please will open a new PR or update its existing one.
The changeset will mostly include version changes and adding relevant information to the `CHANGELOG`.

After testing and making sure everything is ready to release, you can approve and merge the Release Please PR. This will
push a tag with the new version name to the repository.
However you can also push a tag by yourself — it will also start the defined workflows. 

The `build` job runs again, but this time, as the triggering event is a tag push, it will also log in to
the GitHub registry before the build, push the resulting multi-platform images (`linux/amd64`, `linux/arm64`) to the registry,
and build and push the Helm chart to `oci://ghcr.io/distr-sh/charts`.

#### Releasing a new Distr application version (Docker)

On release, the `distr-docker` job in the [hello-distr workflow](.github/workflows/hello-distr.yaml) is started, 
which uploads the artifacts in `deploy/` (`docker-compose.yaml` and `env.template`) to the Distr Hub, 
and makes the new version available to you and your customers. The used version name is the pushed git tag. 

This GitHub action needs to authenticate itself against the Distr Hub, and it needs additional information as to which application the new
version should be added to. Therefore follow these one-time setup steps: 
* Create a Distr Personal Access Token in your account, as described [here](https://distr.sh/docs/integrations/personal-access-token/). 
* Add the Distr PAT to your GitHub repo's secrets and call it `DISTR_TOKEN`. 
* Make sure to have a Distr application in place, to which the newly released version can be attached. If the application does not exist yet,
create it via the Distr Web interface, by giving it a name (like `hello-distr`) and setting the type to `docker`. 
Once created, copy the ID of the application from the web interface (click on the left-most column in the application list).
* Add the copied application ID as a variable to your GitHub repository and call it `DISTR_APPLICATION_ID`. Alternatively you can also 
directly paste it into the workflow file (but please never directly paste any tokens/secrets!). 

See [distr-create-version-action docs](https://github.com/distr-sh/distr-create-version-action/blob/main/README.md#usage) for further information regarding
this GitHub action. 

Note that in this example repo, we set the `api-base` to `https://demo.distr.sh/api/v1`. In order to make use of this in production, 
you should remove this line to use the default Distr Hub (`app.distr.sh`) instead. 

#### Releasing a new Distr application version (Kubernetes)

On release, the `distr-kubernetes` job uploads the Helm chart reference and base values to the Distr Hub.
This works similarly to the Docker path, but uses a Distr application of type `kubernetes` instead. 
The Helm chart is pushed as an OCI artifact to `oci://ghcr.io/distr-sh/charts/hello-distr`, and the compatibility matrix report 
is attached as a visible resource so customers can see which Kubernetes versions were validated.

Follow the same one-time setup steps as for Docker, but:
* Create a separate Distr application with type `kubernetes`.
* Add the application ID as `HELLO_DISTR_HELM_APPLICATION_ID` in your GitHub repository variables.

### Common Requirements

#### Showing the build version in the frontend

We often want to display the software's own version in the user interface. 
To that end we can pass the version name (i.e. the git tag) to the environment of the frontend docker build, which itself
writes this version into a `version.json` file inside the app. The version defined in this file will then be displayed in a 
frontend component. 

To add the argument to the docker build (see `.github/workflows/hello-distr.yaml`):
```yaml
build-args: |
  VERSION=${{ github.ref_name }}
```

To accept this `VERSION` environment variable (see `frontend/Dockerfile`):
```
ARG VERSION
ENV VERSION=${VERSION}
```

To write the version file inside the frontend repo, there is the `frontend/hack/update-frontend-version.js` script:
```javascript
const out = JSON.stringify({version: env['VERSION'] || 'snapshot'}, null, 2)
await writeFile('buildconfig/version.json', out);
```

This script is hooked into the Next.js build process as `prebuild`, see `frontend/package.json`:
```json
"prebuild": "npm run buildconfig",
"buildconfig": "node hack/update-frontend-version.js"
```

### Production Docker Compose file and environment variables

So far we have managed to build and release a new version of `hello-distr` and to publish the deploy artifacts to Distr Hub.
Let's now take a look at these artifacts.

You can find the production compose file at [`deploy/docker-compose.yaml`](deploy/docker-compose.yaml). For all the services to start up and run correctly,
some environment variables need to be passed from the outside. You or your customer (depending on the deployment environment)
will have to set these variables, when deploying the `hello-distr` application via the Distr web interface. 

In order to make this process easier for you and your customers, you can define an optional environment template 
(see [`deploy/env.template`](deploy/env.template)) and upload it to Distr with the `template-file` parameter of the GitHub action. 

This template is a simple text file with `KEY=VALUE` lines. Note: This template is only for the user to set the possible environment
values when deploying the app via Distr — and it will only be shown at the **first** deployment of this app. When later updating
to a newer version, the deploy modal in the Distr web interface will show the previously set variables, not the template!

You can use this template to set recommended values and to leave additional comments. 

The configuration environment variables are:
* `HELLO_DISTR_HOST`: The hostname (without scheme or path) where the app will be reachable.
* `HELLO_DISTR_PROTOCOL`: `http` or `https` (optional, defaults to `http` if not set).
* `HELLO_DISTR_DB_NAME`: The PostgreSQL database name.
* `HELLO_DISTR_DB_USER`: The PostgreSQL user.
* `HELLO_DISTR_DB_PASSWORD`: The PostgreSQL password.

## `hello-distr` in action

Once deployed, the `hello-distr` app will be available at the given hostname (env variable `HELLO_DISTR_HOST`).
The proxy exposes ports 80 and 443.
The user interface will be available at `<protocol>://<hostname>`, and the Python API at `<protocol>://<hostname>/api`
(where `<protocol>` is the value of `HELLO_DISTR_PROTOCOL`). 
The UI consists of only one page showing the deployed version and the latest entry in the `messages` table of the Postgres DB. 
To demonstrate that the API is also publicly available, you can `POST` a newer message to it:

```shell
curl -X POST <protocol>://<your-hostname>/api/messages -d '{"text": "hello distr lol"}'  -H 'Content-Type: application/json'
```

After refreshing the UI, it should display the newly added message. 

## Local Development

**Postgres**

You can install Postgres locally or use Docker to run it in a container.

```shell
docker compose up
```

To start the backend or frontend, please consult the respective `README`s in the subdirectories.
