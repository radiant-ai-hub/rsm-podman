{
  description = "Optional Spark/Hadoop proof environment for the RSM Nix image";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }:
    let
      systems = [ "aarch64-linux" "x86_64-linux" ];
      forAllSystems = f:
        nixpkgs.lib.genAttrs systems (system:
          f (import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          }));
    in
    {
      packages = forAllSystems (pkgs:
        let
          sparkPackagesNoR = pkgs.callPackage "${pkgs.path}/pkgs/applications/networking/cluster/spark" {
            R = null;
            RSupport = false;
          };
          hadoop = pkgs.hadoop;
          java = pkgs.openjdk17_headless;
          spark = sparkPackagesNoR.spark_3_5.overrideAttrs (old: {
            nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
              pkgs.coreutils
              pkgs.gnugrep
              pkgs.gnused
            ];
            postFixup = (old.postFixup or "") + ''
              filtered_hadoop_classpath="$(
                ${hadoop}/bin/hadoop classpath \
                  | tr ':' '\n' \
                  | grep -v '/share/hadoop/yarn' \
                  | grep -v '/spark-[0-9].*-yarn-shuffle[.]jar$' \
                  | paste -sd ':'
              )"

              for spark_bin in "$out"/bin/*; do
                if [ -f "$spark_bin" ]; then
                  sed -i \
                    "s|^\[ -z  \] && export SPARK_DIST_CLASSPATH=.*$|[ -z \"''${SPARK_DIST_CLASSPATH:-}\" ] \&\& export SPARK_DIST_CLASSPATH=$filtered_hadoop_classpath|" \
                    "$spark_bin"
                fi
              done
            '';
          });
        in
        {
          inherit hadoop java spark;

          spark-hadoop-env = pkgs.buildEnv {
            name = "rsm-spark-hadoop-env";
            paths = [
              hadoop
              java
              spark
            ];
            ignoreCollisions = true;
            pathsToLink = [ "/bin" "/lib" "/share" ];
          };

          proof = pkgs.writeShellScriptBin "rsm-spark-hadoop-proof" ''
            set -euo pipefail

            export PATH="${pkgs.lib.makeBinPath [
              pkgs.coreutils
              pkgs.findutils
              pkgs.gnugrep
              hadoop
              java
              pkgs.python313
              spark
            ]}:$PATH"
            export JAVA_HOME="${java}"
            export SPARK_HOME="${spark}"
            export HADOOP_HOME="${hadoop}"
            export SPARK_LOCAL_HOSTNAME="localhost"
            export PYSPARK_PYTHON="${pkgs.python313}/bin/python3"
            export PYSPARK_DRIVER_PYTHON="${pkgs.python313}/bin/python3"

            SPARK_DIST_CLASSPATH="$(
              hadoop classpath \
                | tr ':' '\n' \
                | grep -v '/share/hadoop/yarn' \
                | grep -v '/spark-[0-9].*-yarn-shuffle[.]jar$' \
                | paste -sd ':'
            )"
            export SPARK_DIST_CLASSPATH

            spark_python="$SPARK_HOME/python"
            if [ ! -d "$spark_python/pyspark" ]; then
              spark_python="$(find "$SPARK_HOME" -type d -path '*/python/pyspark' -print -quit)"
              spark_python="''${spark_python%/pyspark}"
            fi

            py4j_zip="$(find "$SPARK_HOME" -type f -path '*/python/lib/py4j-*.zip' -print -quit)"

            if [ ! -d "$spark_python/pyspark" ]; then
              echo "Could not find Spark Python modules under $SPARK_HOME" >&2
              exit 1
            fi

            if [ -z "$py4j_zip" ]; then
              echo "Could not find Spark py4j zip under $SPARK_HOME" >&2
              exit 1
            fi

            export PYTHONPATH="$spark_python:$py4j_zip''${PYTHONPATH:+:$PYTHONPATH}"

            echo "== Hadoop =="
            hadoop version

            echo "== Spark =="
            spark-submit --version

            echo "== PySpark local session =="
            python3 - <<'PY'
from pyspark.sql import SparkSession

spark = (
    SparkSession.builder.master("local[1]")
    .appName("rsm-spark-hadoop-proof")
    .config("spark.ui.enabled", "false")
    .getOrCreate()
)
print("pyspark-count", spark.range(3).count())
spark.stop()
PY
          '';

          default = pkgs.buildEnv {
            name = "rsm-spark-hadoop-default";
            paths = [ hadoop java spark ];
            ignoreCollisions = true;
          };
        });

      apps = forAllSystems (pkgs: {
        proof = {
          type = "app";
          program = "${self.packages.${pkgs.stdenv.hostPlatform.system}.proof}/bin/rsm-spark-hadoop-proof";
          meta.description = "Run the RSM Spark/Hadoop local PySpark proof";
        };
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.python313
            self.packages.${pkgs.stdenv.hostPlatform.system}.spark-hadoop-env
          ];
        };
      });
    };
}
