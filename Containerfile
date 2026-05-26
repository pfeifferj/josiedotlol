# Stage 1: Builder container
FROM fedora:latest AS builder

# Install build dependencies
RUN dnf install -y \
        python3 \
        python3-jinja2 \
        python3-pyyaml \
        python3-markdown \
        python3-requests \
    && dnf clean all

# Copy source files to builder
WORKDIR /build
COPY . .

# Render the static site
RUN python3 scripts/build.py

# Stage 2: Runtime container
FROM quay.io/fedora/httpd-24

# Copy only the generated files from the builder stage
COPY --from=builder --chown=1001:0 /build /var/www/html/

# Copy the Apache configuration
COPY httpd-custom.conf /etc/httpd/conf.d/custom.conf

EXPOSE 8080

CMD run-httpd
