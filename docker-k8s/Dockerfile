# Multi-platform Dockerfile for rsm-msba-k8s
# Supports both ARM64 and AMD64 architectures
# Build with: docker buildx build --platform linux/amd64,linux/arm64 -t your-image:tag .

# Use the latest tag and let Docker buildx handle platform selection automatically
# Updated to match the latest versions from individual Dockerfiles
FROM quay.io/jupyter/pyspark-notebook:2025-12-15

USER root

# Define build argument and set it as an environment variable in one step
ARG IMAGE_VERSION
ENV IMAGE_VERSION=${IMAGE_VERSION}

# Get platform info for conditional logic
ARG TARGETPLATFORM
ARG TARGETOS
ARG TARGETARCH

# Set platform-specific environment variables
# Note: IMAGE_NAME and platform-specific vars will be set dynamically below

# Ensure NB_USER is set (some base images might not have it)
ENV NB_USER=${NB_USER:-jovyan}

# Python env variables
# ENV PYARROW_VERSION="20.0.0"

# R and Posit related env variables
ENV QUARTO_VERSION="1.9.13"
# ENV TERM=xterm
ENV PATH="/usr/local/bin:$PATH"

# Postgres env variables
ENV POSTGRES_VERSION=16
ENV PGPASSWORD=postgres

# Jupyter and shell environment setup
ARG RSMBASE=/home/${NB_USER}/.rsm-msba
ENV RSMBASE=${RSMBASE} \
    SHELL=/bin/zsh \
    ZDOTDIR=/home/${NB_USER}/.rsm-msba/zsh

# Set platform-specific variables for build time (PGWEB_FILE needed for binary download)
# Note: JAVA_HOME is set at runtime by /etc/profile.d/rsm-env.sh
RUN if [ "${TARGETARCH}" = "arm64" ]; then \
    echo "export PGWEB_FILE=pgweb_linux_arm64_v7.zip" >> /etc/environment; \
    elif [ "${TARGETARCH}" = "amd64" ]; then \
    echo "export PGWEB_FILE=pgweb_linux_amd64.zip" >> /etc/environment; \
    else \
    echo "Unsupported architecture: ${TARGETARCH}" && exit 1; \
    fi

# Source the environment file to make PGWEB_FILE available for build
RUN . /etc/environment

# Add autojump to initial package installation
COPY files/init-apt.sh setup.sh
RUN chmod +x setup.sh && \
    ./setup.sh && \
    rm setup.sh

COPY files/postgres/postgresql.conf /etc/postgresql/${POSTGRES_VERSION}/main/postgresql.conf
COPY files/postgres/pg_hba.conf /etc/postgresql/${POSTGRES_VERSION}/main/pg_hba.conf

COPY files/postgres/install-postgres-mp.sh setup.sh
RUN chmod +x setup.sh && \
    ./setup.sh && \
    rm setup.sh

# Copy postgres init script for runtime initialization (fresh volume mounts)
COPY files/postgres/init-postgres-db.sh /usr/local/bin/init-postgres-db.sh
RUN chmod +x /usr/local/bin/init-postgres-db.sh

COPY files/install-sshd.sh setup.sh
RUN chmod +x setup.sh && \
    ./setup.sh && \
    rm setup.sh

COPY files/install-quarto.sh setup.sh
RUN chmod +x setup.sh && \
    ./setup.sh && \
    rm setup.sh

COPY files/install-uv.sh setup.sh
RUN chmod +x setup.sh && \
    ./setup.sh && \
    rm setup.sh

# Setup hadoop
# JAVA_HOME is set via platform detection above
ENV HADOOP_VERSION=3.3.4
ENV HADOOP_HOME=/opt/hadoop
ENV HADOOP_CONF_DIR=$HADOOP_HOME/etc/hadoop
COPY files/install-hadoop.sh setup.sh
RUN chmod +x setup.sh && \
    ./setup.sh && \
    rm setup.sh

# Hadoop configuration
ADD files/scalable_analytics/core-site.xml $HADOOP_HOME/etc/hadoop/
ADD files/scalable_analytics/hdfs-site.xml $HADOOP_HOME/etc/hadoop/
ADD files/scalable_analytics/init-dfs.sh /opt/hadoop/
ADD files/scalable_analytics/start-dfs.sh /opt/hadoop/
ADD files/scalable_analytics/stop-dfs.sh /opt/hadoop/
RUN chown -R ${NB_USER} ${HADOOP_HOME} && \
    chmod 755 ${HADOOP_HOME}/*.sh && \
    chmod 755 /usr/bin/hadoop
ENV PATH=$PATH:$HADOOP_HOME/bin

# Install pgweb with platform-specific binary
# Run pgweb from the terminal use pgweb --bind=0.0.0.0 --listen=8000
# Once setup has been run inside the container there should be an alias pgw
RUN . /etc/environment && \
    wget -O pgweb.zip https://github.com/sosedoff/pgweb/releases/download/v0.11.11/$PGWEB_FILE && \
    unzip pgweb.zip -d pgweb_dir && \
    mv pgweb_dir/* /usr/local/bin/pgweb_binary && \
    rm -rf pgweb_dir pgweb.zip

# Create log directories with proper permissions for rootless operation
RUN mkdir -p /var/log/postgresql /var/log/sshd && \
    chown jovyan:users /var/log/postgresql && \
    chmod 750 /var/log/postgresql

# Oh-my-zsh and other zsh setup
COPY files/install-ohmyzsh.sh setup.sh
RUN chmod +x setup.sh && \
    ./setup.sh && \
    rm setup.sh

# Setup the GitHub CLI
COPY files/install-gh.sh setup.sh
RUN chmod +x setup.sh && \
    ./setup.sh && \
    rm setup.sh

# RSM environment variables (JAVA_HOME, PYTHONPATH, etc.)
COPY files/profile.d/rsm-env.sh /etc/profile.d/rsm-env.sh
RUN chmod 644 /etc/profile.d/rsm-env.sh && \
    echo 'source /etc/profile.d/rsm-env.sh' >> /etc/zsh/zshenv

# Copying over CLI scripts
COPY files/zsh/zshrc /etc/skel/.zshrc
COPY files/zsh/p10k.zsh /etc/skel/.p10k.zsh
COPY files/zsh/usethis /usr/local/bin/usethis
COPY files/zsh/interactive-usethis.sh /usr/local/bin/iusethis
COPY files/zsh/github.sh /usr/local/bin/github
COPY files/zsh/setup.sh /usr/local/bin/setup
COPY files/zsh/menu.sh /usr/local/bin/menu

RUN fix-permissions /etc/skel && \
    fix-permissions /usr/local/bin && \
    chmod 755 /usr/local/bin/*

# Startup script
COPY files/start-container.sh /usr/local/bin/
COPY files/sshd/sshd_config /etc/ssh/sshd_config
RUN chmod +x /usr/local/bin/start-container.sh

RUN touch /var/log/sshd/sshd.log && \
    chown ${NB_USER}:${NB_GID:-users} /var/log/sshd/sshd.log && \
    chmod 640 /var/log/sshd/sshd.log

EXPOSE 2222 8282 8765

CMD ["/usr/local/bin/start-container.sh"]

# Switch back to jovyan to avoid accidental container runs as root
USER ${NB_UID}
ENV HOME=/home/${NB_USER}
# WORKDIR "${HOME}"
