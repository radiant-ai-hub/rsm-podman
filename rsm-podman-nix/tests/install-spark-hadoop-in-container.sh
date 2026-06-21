#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "This installer must run as root inside the container." >&2
  exit 1
fi

repo="${RSM_REPO:-/workspace/rsm-podman}"
flake="${RSM_SPARK_HADOOP_FLAKE:-$repo/rsm-podman-nix/spark-hadoop}"
analytics_dir="${RSM_ANALYTICS_DIR:-$repo/files/scalable_analytics}"
runtime_user="${RSM_USERNAME:-${NB_USER:-rsmuser}}"

if [ ! -d "$flake" ]; then
  echo "Spark/Hadoop flake not found: $flake" >&2
  exit 1
fi

if [ ! -d "$analytics_dir" ]; then
  echo "Scalable analytics files not found: $analytics_dir" >&2
  exit 1
fi

if ! awk -F: -v name="$runtime_user" '$1 == name { found=1 } END { exit !found }' /etc/passwd; then
  echo "Runtime user does not exist in /etc/passwd: $runtime_user" >&2
  exit 1
fi

nix_flags=(--extra-experimental-features "nix-command flakes")
build_links="/tmp/rsm-spark-hadoop-links"

rm -rf "$build_links"
mkdir -p "$build_links"
chown "$runtime_user:$(id -gn "$runtime_user")" "$build_links"

gosu "$runtime_user" nix "${nix_flags[@]}" build "$flake#spark" --out-link "$build_links/spark"
gosu "$runtime_user" nix "${nix_flags[@]}" build "$flake#hadoop" --out-link "$build_links/hadoop"
gosu "$runtime_user" nix "${nix_flags[@]}" build "$flake#java" --out-link "$build_links/java"

spark_store="$(readlink -f "$build_links/spark")"
hadoop_store="$(readlink -f "$build_links/hadoop")"
java_store="$(readlink -f "$build_links/java")"
runtime_group="$(id -gn "$runtime_user")"
hadoop_tmp="/tmp/hadoop-$runtime_user"

ln -sfn "$spark_store" /opt/rsm-spark-store
ln -sfn "$hadoop_store" /opt/rsm-hadoop-store
ln -sfn "$java_store" /opt/rsm-java-store

rm -rf /usr/local/spark /opt/hadoop
ln -s "$spark_store" /usr/local/spark

mkdir -p /opt/hadoop/logs "$hadoop_tmp/dfs/name" "$hadoop_tmp/dfs/data" "$hadoop_tmp/pids"
for item in bin include lib libexec share; do
  if [ -e "$hadoop_store/$item" ]; then
    ln -s "$hadoop_store/$item" "/opt/hadoop/$item"
  fi
done

cp -a "$hadoop_store/etc" /opt/hadoop/etc
cp "$analytics_dir/core-site.xml" /opt/hadoop/etc/hadoop/core-site.xml
cp "$analytics_dir/hdfs-site.xml" /opt/hadoop/etc/hadoop/hdfs-site.xml
chmod -R u+rwX,g+rwX /opt/hadoop/etc

{
  echo "export JAVA_HOME=$java_store"
  echo "export HADOOP_LOG_DIR=/opt/hadoop/logs"
  echo "export HADOOP_PID_DIR=$hadoop_tmp/pids"
} >> /opt/hadoop/etc/hadoop/hadoop-env.sh

python3 - "$runtime_user" /opt/hadoop/etc/hadoop/hdfs-site.xml <<'PY'
import sys
import xml.etree.ElementTree as ET

user, path = sys.argv[1], sys.argv[2]
tree = ET.parse(path)
root = tree.getroot()

values = {
    "dfs.replication": "1",
    "dfs.permissions.enabled": "false",
    "dfs.namenode.name.dir": f"file:///tmp/hadoop-{user}/dfs/name",
    "dfs.datanode.data.dir": f"file:///tmp/hadoop-{user}/dfs/data",
}

existing = {}
for prop in root.findall("property"):
    name = prop.find("name")
    value = prop.find("value")
    if name is not None and value is not None:
        existing[name.text] = value

for key, val in values.items():
    if key in existing:
        existing[key].text = val
    else:
        prop = ET.SubElement(root, "property")
        name = ET.SubElement(prop, "name")
        name.text = key
        value = ET.SubElement(prop, "value")
        value.text = val

ET.indent(tree, space="    ")
tree.write(path, encoding="UTF-8", xml_declaration=True)
PY

cat > /opt/hadoop/init-dfs.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

: "${HADOOP_HOME:=/opt/hadoop}"
: "${HADOOP_CONF_DIR:=$HADOOP_HOME/etc/hadoop}"

hadoop_user="${USER:-${RSM_USERNAME:-rsmuser}}"
hadoop_tmp="/tmp/hadoop-$hadoop_user"

mkdir -p "$hadoop_tmp/dfs/name" "$hadoop_tmp/dfs/data" "$HADOOP_HOME/logs"

if [ -f "$HADOOP_CONF_DIR/log4j.properties" ] && ! grep -q "NativeCodeLoader=ERROR" "$HADOOP_CONF_DIR/log4j.properties"; then
  {
    echo "# Suppress NativeCodeLoader warning"
    echo "log4j.logger.org.apache.hadoop.util.NativeCodeLoader=ERROR,console"
  } >> "$HADOOP_CONF_DIR/log4j.properties"
fi

rm -rf "$hadoop_tmp/dfs/name" "$hadoop_tmp/dfs/data"
mkdir -p "$hadoop_tmp/dfs/name" "$hadoop_tmp/dfs/data"

"$HADOOP_HOME/bin/hdfs" namenode -format -force -nonInteractive
EOF

cat > /opt/hadoop/start-dfs.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "Starting HDFS ..."
hdfs --daemon start namenode
hdfs --daemon start datanode
hdfs --daemon start secondarynamenode
EOF

cat > /opt/hadoop/stop-dfs.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "Stopping HDFS ..."
hdfs --daemon stop namenode || true
hdfs --daemon stop datanode || true
hdfs --daemon stop secondarynamenode || true
EOF

cat > /etc/profile.d/rsm-spark-hadoop.sh <<EOF
export JAVA_HOME="$java_store"
export SPARK_HOME="/usr/local/spark"
export HADOOP_HOME="/opt/hadoop"
export HADOOP_CONF_DIR="/opt/hadoop/etc/hadoop"
export HADOOP_LOG_DIR="/opt/hadoop/logs"
export HADOOP_PID_DIR="$hadoop_tmp/pids"
export SPARK_LOCAL_HOSTNAME="localhost"
export PYSPARK_PYTHON="/opt/base-uv/.venv/bin/python"
export PYSPARK_DRIVER_PYTHON="/opt/base-uv/.venv/bin/python"
export PATH="\$SPARK_HOME/bin:\$HADOOP_HOME/bin:\$JAVA_HOME/bin:\$PATH"

if [ -x "\$HADOOP_HOME/bin/hadoop" ]; then
  export SPARK_DIST_CLASSPATH="\$("\$HADOOP_HOME/bin/hadoop" classpath | tr ':' '\n' | grep -v '/share/hadoop/yarn' | grep -v '/spark-[0-9].*-yarn-shuffle[.]jar$' | paste -sd ':')"
fi

_spark_python="\$SPARK_HOME/python"
_py4j_zip="\$(find -L "\$SPARK_HOME" -type f -path '*/python/lib/py4j-*.zip' -print -quit 2>/dev/null || true)"
if [ -n "\$_py4j_zip" ]; then
  export PYTHONPATH="\$_spark_python:\$_py4j_zip\${PYTHONPATH:+:\$PYTHONPATH}"
fi
unset _spark_python _py4j_zip
EOF

ln -sf /opt/hadoop/bin/hadoop /usr/bin/hadoop
ln -sf /opt/hadoop/bin/hdfs /usr/bin/hdfs
ln -sf "$java_store/bin/jps" /usr/bin/jps

chmod 755 /opt/hadoop/*.sh
chmod -R u+rwX,g+rwX /opt/hadoop/etc /opt/hadoop/logs "$hadoop_tmp"
chown -R "$runtime_user:$runtime_group" /opt/hadoop "$hadoop_tmp"
chown -h "$runtime_user:$runtime_group" /usr/local/spark /usr/bin/hadoop /usr/bin/hdfs /usr/bin/jps

echo "Installed optional Spark/Hadoop stack:"
echo "  SPARK_HOME=/usr/local/spark -> $spark_store"
echo "  HADOOP_HOME=/opt/hadoop -> $hadoop_store"
echo "  JAVA_HOME=$java_store"
