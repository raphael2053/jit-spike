FROM ubuntu:22.04

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    jq \
    git \
    sudo \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create runner user
RUN useradd -m -s /bin/bash runner && \
    echo "runner ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Download GitHub Actions Runner (architecture-aware)
WORKDIR /home/runner
RUN RUNNER_VERSION="2.329.0" && \
    ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "amd64" ]; then \
        RUNNER_ARCH="x64"; \
    elif [ "$ARCH" = "arm64" ]; then \
        RUNNER_ARCH="arm64"; \
    else \
        echo "Unsupported architecture: $ARCH" && exit 1; \
    fi && \
    echo "Downloading runner for architecture: $RUNNER_ARCH" && \
    curl -o actions-runner-linux.tar.gz -L \
    "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz" && \
    tar xzf actions-runner-linux.tar.gz && \
    rm actions-runner-linux.tar.gz && \
    chown -R runner:runner /home/runner

USER runner
WORKDIR /home/runner

# Default command (will be overridden)
CMD ["/bin/bash"]