# Dockerfile writing best practices

* Use an appropriate / minimal base image that's actively maintained and responsive to security updates. The current recommendation is [`minideb`](https://github.com/bitnami/minideb) as it's minimal and well-maintained from a security standpoint.  Bitnami offers minideb based images for many common use cases such as [`bitnami/java`](https://hub.docker.com/r/bitnami/java/) for OpenJDK and [`bitnami/postgresql`](https://hub.docker.com/r/bitnami/postgresql/).
* Minimize number of instructions being used as each instruction like `ENV`, `ARG` generates a layer which can be separately cached for subsequent rebuilds
    - Collapse instructions where allowed (i.e. `ENV` statements can be combined, `ARG` cannot). Typically multiple `RUN` instructions are unnecessary and should be combined.
    - The one exception is when a specific `ENV` value depends on another `ENV` value. In such instances, another `ENV` block must be introduced to consume the previously declared value. 
* Prefer ordering instructions to prioritize cacheable instructions earlier
    - `ENV`, `VOLUME`, `ARG`, `EXPOSE`, `ENTRYPOINT`, `CMD`, `HEALTHCHECK`, `ADD` (i.e. from urls) and `COPY` (in some cases) are examples. The `RUN` instruction always prevents caching from the point it is introduced forward.
* Only use `ENV` for values intended to be set by container consumers - don't use them as general purpose variables, as the presence of an `ENV` var typically signals a configurable setting to consumers.
* Use `ARG` for variables that can be supplied at build-time *and* as variables used during the build that shouldn't be surfaced to end users
    - Use `ARG lower` for arguments intended to be supplied by `--build-args`
    - Use `ARG UPPER` for arguments intended to be as environment variables exposed only during build-time
* Always add standard static Puppet metadata values early to the `Dockerfile`:

```
LABEL org.label-schema.maintainer="Puppet Release Team <release@puppet.com>" \
org.label-schema.vendor="Puppet" \
org.label-schema.url="https://github.com/puppetlabs/pe-puppetdb" \
org.label-schema.name="PE Puppet Server" \
org.label-schema.license="Apache-2.0" \
org.label-schema.vcs-url="https://github.com/puppetlabs/pe-puppetdb" \
org.label-schema.schema-version="1.0" \
org.label-schema.dockerfile="/Dockerfile"
```

Add metadata labels determined dynamically near the end of the `Dockerfile`:

```
LABEL org.label-schema.version="$version" \
org.label-schema.vcs-ref="$vcs_ref" \
org.label-schema.build-date="$build_date"
```

* `EXPOSE` is useful as documentation, but doesn't actually result in open ports at runtime
* Use an init process for multi-process containers to properly:
    - exit when child processes terminate
    - fulfill PID 1 responsibilities (zombie reaping and signal forwarding)

  A popular solution across containers is to to run custom entrypoint scripts out of the `docker-entrypoint.d` directory with tini like:

```
ENTRYPOINT ["/tini", "-g", "--", "/docker-entrypoint.sh"]
CMD ["foreground"]
```

  This also allows for running multiple processes, which `tini` and `dumb-init` don't typically support - but because of the use of Bash, also loses signal handling capabilities.

  CLI run and exit style containers are typically invoked directly like

```
ENTRYPOINT ["/opt/puppetlabs/bin/puppet"]
```

* Define a `HEALTHCHECK` to inform Docker when a container service is ready. Docker / compose are still useful as testing tools and this check can be leveraged there. This check typically should not consider downstream service dependencies in other containers. 

NOTE: this check is not used by Kubernetes as it has separate probes for `startup`, `liveness` and `readiness` which have different semantics.

* Define a `VOLUME` for each area of the file system that should persist user data that survives upgrades. If a user doesn't map the `VOLUME` to a local path via bind mount or to a named volume, Docker creates an anonymous volume.

NOTE: `VOLUME` directories should be empty at startup, because Kubernetes will shadow the contents with an empty `VOLUME`, unlike Docker which will copy files from the shadowed image layers to the new `VOLUME`.
* Use the `USER` instruction to run as a high-numbered non-root user created in the container during the main `RUN` instruction. This better supports security guidelines for Kubernetes and is typically necessary to support OpenShift.
    - When using `COPY` it is often useful to supply `--chown=user:group` to match the `USER`.
* When installing packages during a `RUN` instruction, be sure to cleanup any package manager files from disk to reduce shipping container size.
* Always add the current `Dockerfile` in a step at the end with `COPY Dockerfile /` as a reference

### Tool considerations

* Optimize around use of [buildkit](https://github.com/moby/buildkit) / [buildx](https://github.com/docker/buildx), as it provides:
    - Improved caching for repeat builds / shorter build times
    - Ability to execute instructions in parallel where possible
    - Ability to intelligently skip unnecessary intermediate `Dockerfile` instructions
* Use [hadolint](https://github.com/hadolint/hadolint) to scan the Dockerfile / embedded shell scripts (hadolint includes [shellcheck](https://www.shellcheck.net/))
* Use an image scanner

### External References

* [Choosing an init process for multi-process containers
](https://ahmet.im/blog/minimal-init-process-for-containers/)
* [Sysdig Top 20 Dockerfile best practices](https://sysdig.com/blog/dockerfile-best-practices/)
* [Faster CI Builds with Docker Layer Caching and Buildkit](https://testdriven.io/blog/faster-ci-builds-with-docker-cache/)
* [Advantages of Non-Root Containers](https://docs.bitnami.com/tutorials/work-with-non-root-containers/)
