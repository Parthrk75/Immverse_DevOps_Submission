#!/usr/bin/env bash
# Installs the CI toolbox used by the pipelines. Versions pinned; verify URLs when bumping.
set -euo pipefail
T=/tmp/tools; mkdir -p $T /usr/local/bin; cd $T
dl(){ curl -fsSL "$1" -o "$2"; }
dl https://github.com/aquasecurity/trivy/releases/download/v0.55.2/trivy_0.55.2_Linux-64bit.tar.gz trivy.tgz && tar xzf trivy.tgz trivy && mv trivy /usr/local/bin/
dl https://github.com/anchore/syft/releases/download/v1.14.1/syft_1.14.1_linux_amd64.tar.gz syft.tgz && tar xzf syft.tgz syft && mv syft /usr/local/bin/
dl https://github.com/sigstore/cosign/releases/download/v2.4.1/cosign-linux-amd64 /usr/local/bin/cosign && chmod +x /usr/local/bin/cosign
dl https://dl.k8s.io/release/v1.31.1/bin/linux/amd64/kubectl /usr/local/bin/kubectl && chmod +x /usr/local/bin/kubectl
dl https://get.helm.sh/helm-v3.16.2-linux-amd64.tar.gz helm.tgz && tar xzf helm.tgz && mv linux-amd64/helm /usr/local/bin/
dl https://releases.hashicorp.com/terraform/1.9.8/terraform_1.9.8_linux_amd64.zip tf.zip && unzip -q tf.zip && mv terraform /usr/local/bin/
dl https://github.com/terraform-linters/tflint/releases/download/v0.53.0/tflint_linux_amd64.zip tfl.zip && unzip -q tfl.zip && mv tflint /usr/local/bin/
dl https://github.com/open-policy-agent/conftest/releases/download/v0.55.0/conftest_0.55.0_Linux_x86_64.tar.gz ct.tgz && tar xzf ct.tgz conftest && mv conftest /usr/local/bin/
pip3 install --no-cache-dir --break-system-packages pyyaml checkov
rm -rf $T
