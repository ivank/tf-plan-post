FROM alpine:latest

LABEL org.opencontainers.image.source=https://github.com/ivank/tf-plan-post
LABEL org.opencontainers.image.description="Terraform Plan Post"
LABEL org.opencontainers.image.licenses=MIT
 
ARG BERGLAS_VERSION=2.0.6
ARG GH_VERSION=2.10.1
ARG JWT_VERSION=6.2.0

RUN apk add --no-cache curl bash

RUN curl --location https://github.com/GoogleCloudPlatform/berglas/releases/download/v${BERGLAS_VERSION}/berglas_${BERGLAS_VERSION}_linux_amd64.tar.gz \
    | tar -xzC /usr/local/bin

RUN curl --location https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz \
    | tar --strip-components=2 -xzC /usr/local/bin gh_${GH_VERSION}_linux_amd64/bin/gh

RUN curl --location https://github.com/mike-engel/jwt-cli/releases/download/${JWT_VERSION}/jwt-linux.tar.gz \
    | tar -xzC /usr/local/bin
    
COPY tf-plan-post.sh /builder/tf-plan-post.sh

ENTRYPOINT ["bash","/builder/tf-plan-post.sh"]