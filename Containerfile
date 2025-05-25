# Stage 1: Builder container
FROM fedora:latest AS builder

# Install build dependencies
RUN dnf install -y pandoc perl && dnf clean all

# Copy source files to builder
WORKDIR /build
COPY . .

# Run the blog build script to generate static HTML files
RUN ./scripts/blog-build.sh

# Stage 2: Runtime container
FROM quay.io/fedora/httpd-24

# Copy only the generated files from the builder stage
COPY --from=builder --chown=1001:0 /build /var/www/html/

# Copy the Apache configuration
COPY httpd-custom.conf /etc/httpd/conf.d/custom.conf

EXPOSE 8080

CMD run-httpd
