FROM debian:11-slim
RUN apt-get update && apt-get install -y curl git procps && apt-get clean

# Inštalácia Kubectl pre ovládanie klastra
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    && chmod +x kubectl && mv kubectl /usr/local/bin/

COPY run.sh /run.sh
ENTRYPOINT ["/bin/bash", "/run.sh"]
