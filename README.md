# Vector (Hardware-Optimized Builds)

[![Daily Release Check](https://github.com/jimmystewpot/vector-optimised/actions/workflows/release.yml/badge.svg)](https://github.com/jimmystewpot/vector-optimised/actions/workflows/release.yml)
[![GitHub Release](https://img.shields.io/github/v/release/jimmystewpot/vector-optimised?include_prereleases&style=flat-square)](https://github.com/jimmystewpot/vector-optimised/releases)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

High-performance, automated, hardware-optimized distributions of [Vector](https://github.com/vectordotdev/vector) built specifically for modern cloud server architectures.

---

## Why Hardware-Optimized Builds?

Upstream Vector distributes generic pre-compiled binaries targeting baseline CPU architectures (e.g., generic `aarch64` and generic `x86-64`). To ensure compatibility with early 64-bit processors, those builds avoid instruction extensions that exist on modern cloud CPUs:

1. **ARM64 (`aarch64-unknown-linux-gnu-lse`)**:
   - Compiled with **ARM Large System Extensions (`+lse`)** and tuned for `neoverse-n1`.
   - Replaces slow out-of-line atomic trampoline helpers and LL/SC (`ldxr`/`stxr`) retry loops with inlined single-instruction `ldadd`, `cas`, and `swp` primitives.
   - Eliminates atomic synchronization bottlenecks across high-throughput components like Tokio worker threads, buffer queues, and `rdkafka` / `librdkafka`.
   - **Empirical Results**: Delivers a **+4.78% throughput increase** and a **1.53 MB (4%) reduction in binary size**.
   - **Target Hardware**: AWS Graviton 2/3/4, Google Cloud Tau T2A, Ampere Altra, Azure Cobalt 100.

2. **x86_64 (`x86_64-unknown-linux-gnu-v3`)**:
   - Compiled targeting the **`x86-64-v3`** microarchitecture level.
   - Enables AVX, AVX2, BMI1, BMI2, FMA, F16C, and LZCNT vectorization.
   - Accelerates UTF-8 validation (`simdutf8`), base64 encoding (`base64-simd`), hashing, VRL string operations, and compression codecs (`zstd`, `lz4`).
   - **Target Hardware**: Modern Intel Xeon (Haswell+) and AMD EPYC (Zen 1+) cloud instances.

---

## Benchmark Comparison (Neoverse-N1 / Ampere Altra)

Benchmarked on Google Cloud Compute Engine (`t2a-standard-16`, 16 vCPUs Neoverse-N1, 64 GB RAM) processing 500,000 JSON log events through a realistic `demo_logs` $\rightarrow$ `remap` (VRL parsing & enrichments) $\rightarrow$ `blackhole` pipeline:

| Metric | Upstream Generic (`aarch64`) | Hardware-Optimized (`+lse`) | Improvement |
|:---|:---:|:---:|:---:|
| **Event Throughput** | 58,378 events/sec | **61,171 events/sec** | **+4.78% faster** |
| **Wall Clock Duration** | 8.565 s | **8.174 s** | **−4.57% processing time** |
| **Stripped Binary Size** | 37.68 MB | **36.16 MB** | **−1.53 MB smaller (−4.06%)** |
| **Counter Atomic Contention** | 104.75 Melem/s | **111.27 Melem/s** | **+6.12% throughput** |
| **CAS Loop Contention (4 threads)**| 26.50 Melem/s | **30.79 Melem/s** | **+14.50% throughput** |
| **Histogram Record (1 thread)** | 29.53 Melem/s | **34.37 Melem/s** | **+17.29% throughput** |

---

## Quick Install

Download and unpack the latest release for your architecture from the [Releases](https://github.com/jimmystewpot/vector-optimised/releases) page:

### For ARM64 Cloud Servers (AWS Graviton, GCP Tau, Ampere Altra)
```bash
LATEST_TAG=$(curl -s https://api.github.com/repos/jimmystewpot/vector-optimised/releases/latest | jq -r .tag_name)
curl -L -o vector.tar.gz "https://github.com/jimmystewpot/vector-optimised/releases/download/${LATEST_TAG}/vector-${LATEST_TAG}-aarch64-unknown-linux-gnu-lse.tar.gz"

tar -xzf vector.tar.gz
sudo mv vector-*/bin/vector /usr/local/bin/
vector --version
```

### For Modern x86_64 Servers (Intel / AMD with AVX2)
```bash
LATEST_TAG=$(curl -s https://api.github.com/repos/jimmystewpot/vector-optimised/releases/latest | jq -r .tag_name)
curl -L -o vector.tar.gz "https://github.com/jimmystewpot/vector-optimised/releases/download/${LATEST_TAG}/vector-${LATEST_TAG}-x86_64-unknown-linux-gnu-v3.tar.gz"

tar -xzf vector.tar.gz
sudo mv vector-*/bin/vector /usr/local/bin/
vector --version
```

---

## Verifying Checksums

Every release includes a cryptographic `SHA256SUMS` file:

```bash
curl -L -O "https://github.com/jimmystewpot/vector-optimised/releases/download/${LATEST_TAG}/SHA256SUMS"
sha256sum --ignore-missing -c SHA256SUMS
```

---

## How It Works

This repository is an automated build and release orchestrator:
1. **Upstream Detection**: A scheduled GitHub Actions workflow runs daily at 02:00 UTC to inspect [vectordotdev/vector](https://github.com/vectordotdev/vector) for new official releases.
2. **Hybrid Runner Compilation**:
   - **x86_64 Builds**: Run locally on a high-throughput Kubernetes ARC runner scale set (`runs-on: arc-runner-set`).
   - **ARM64 Builds**: Dynamically spin up a high-core ephemeral Google Cloud `t2a-standard-16` instance (Ampere Altra), build the binary with native LSE and CFLAGS, and automatically terminate upon completion.
3. **Packaging & Release**: Packages stripped binaries, sample configs, and systemd units into `.tar.gz` archives, computes checksums, and publishes directly to GitHub Releases.

---

## License

This project packages official releases of [Vector](https://github.com/vectordotdev/vector). Vector is licensed under the [Mozilla Public License 2.0 (MPL-2.0)](https://www.mozilla.org/en-US/MPL/2.0/) or [Apache-2.0](LICENSE).
