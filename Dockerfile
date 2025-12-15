FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive
ENV RUNNER_DIR=/actions-runner
ENV PATH=$PATH:$RUNNER_DIR

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      curl jq ca-certificates tar git libicu-dev libssl-dev libgssapi-krb5-2 iputils-ping && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /tmp

# Download latest runner linux-arm64 asset using the GitHub Releases API (robust to filename/version)
RUN DOWNLOAD_URL=$(curl -sSL https://api.github.com/repos/actions/runner/releases/latest \
      | jq -r '.assets[] | select(.name | test("linux-arm64")) | .browser_download_url') && \
    if [ -z "$DOWNLOAD_URL" ]; then echo "No linux-arm64 runner asset found" && exit 1; fi && \
    curl -fsSL -o runner.tar.gz "$DOWNLOAD_URL" && \
    mkdir -p $RUNNER_DIR && \
    tar xzf runner.tar.gz -C $RUNNER_DIR && \
    rm runner.tar.gz

# Copy entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR $RUNNER_DIR

ENTRYPOINT ["/entrypoint.sh"]
