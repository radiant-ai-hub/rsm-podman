#!/bin/bash
# RSM environment variables - sourced by login shells

# JAVA_HOME: Source from /etc/environment (set at build time) or detect
if [ -f /etc/environment ]; then
    . /etc/environment
fi

if [ -z "$JAVA_HOME" ]; then
    ARCH=$(uname -m)
    if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
        export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-arm64
    else
        export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
    fi
fi

# Spark and Hadoop
export SPARK_HOME=/usr/local/spark
export HADOOP_HOME=/opt/hadoop

# Detect py4j version dynamically
PY4J_ZIP=$(ls ${SPARK_HOME}/python/lib/py4j-*.zip 2>/dev/null | head -1)
if [ -n "$PY4J_ZIP" ]; then
    export PYTHONPATH=${SPARK_HOME}/python:${PY4J_ZIP}:${PYTHONPATH}
else
    export PYTHONPATH=${SPARK_HOME}/python:${PYTHONPATH}
fi

# Add to PATH if not already present
case ":$PATH:" in
    *":${HADOOP_HOME}/bin:"*) ;;
    *) export PATH=${HADOOP_HOME}/bin:${SPARK_HOME}/bin:${PATH} ;;
esac
