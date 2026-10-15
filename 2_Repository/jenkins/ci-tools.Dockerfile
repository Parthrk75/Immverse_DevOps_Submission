# Image used by the Kubernetes agent pod (jenkins/agent-pod.yaml, container "tools").
#   docker build -f jenkins/ci-tools.Dockerfile -t ghcr.io/immverse/ci-tools:1.0 jenkins && docker push ...
FROM ubuntu:24.04
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates unzip git jq python3 python3-pip gnupg \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /usr/share/keyrings/gh.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/gh.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/gh.list \
    && apt-get update && apt-get install -y gh && rm -rf /var/lib/apt/lists/*
COPY install-tools.sh /tmp/install-tools.sh
RUN /tmp/install-tools.sh
CMD ["sleep", "infinity"]
