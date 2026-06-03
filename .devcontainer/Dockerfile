FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates gnupg lsb-release \
    && curl -sL https://aka.ms/InstallAzureCLIDeb | bash \
    && curl -fsSL https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb -o packages-microsoft-prod.deb \
    && dpkg -i packages-microsoft-prod.deb \
    && rm packages-microsoft-prod.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends powershell \
    && curl -fsSL https://aka.ms/install-azd.sh | bash \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
