# Optional Spark/Hadoop Flake

This flake keeps Spark and Hadoop out of the default Nix container image while
providing a concrete proof target.

Run the proof on the host:

```bash
nix run ./rsm-podman-nix/spark-hadoop#proof
```

Run the container integration test:

```bash
ENGINE=docker IMAGE=rsm-podman-nix:dev PLATFORM=linux/arm64 \
  rsm-podman-nix/tests/container-spark-hadoop-notebooks.sh
```

The integration test starts a fresh container, resolves the runtime user from
`RSM_USER_EMAIL`, installs Spark/Hadoop from this optional flake into the
running container, runs command smoke checks, and executes the existing
notebooks in `files/scalable_analytics/test` from an isolated temporary copy.

The proof checks:

- `hadoop version`
- `spark-submit --version`
- a local PySpark `SparkSession` using Spark's bundled Python modules
- the existing PySpark and HDFS notebooks

Verified on local `aarch64-linux`:

- Hadoop `3.4.0`
- Spark `3.5.5`
- PySpark local session prints `pyspark-count 3`

Measured size impact on `aarch64-linux`:

- dry-run proof fetch: about 1.9 GiB
- dry-run proof unpacked size: about 2.9 GiB
- final proof/environment closure: about 3.0 GiB

Implementation notes:

- Spark is built with `RSupport = false`.
- The Spark wrapper is patched to respect `SPARK_DIST_CLASSPATH`.
- Hadoop's YARN classpath entries are filtered for local PySpark mode because
  nixpkgs Hadoop currently includes a Spark 4 YARN shuffle jar that introduces
  Scala 2.13 classes into Spark 3.5's Scala 2.12 runtime.

Because this stack is about 3.0 GiB unpacked even after trimming SparkR, it
should remain optional unless a course needs it in every image.
