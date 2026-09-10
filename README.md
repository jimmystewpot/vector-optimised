# Vector (Hardware-Optimized Builds)

[![Daily Release Check](https://github.com/jimmystewpot/vector-optimised/actions/workflows/release.yml/badge.svg)](https://github.com/jimmystewpot/vector-optimised/actions/workflows/release.yml)
[![GitHub Release](https://img.shields.io/github/v/release/jimmystewpot/vector-optimised?include_prereleases&style=flat-square)](https://github.com/jimmystewpot/vector-optimised/releases)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

High-performance, automated, hardware-optimized distributions of [Vector](https://github.com/vectordotdev/vector) engineered for **maximum throughput**, **lower end-to-end latency**, and **reduced CPU overhead** on modern cloud server architectures.

---

## Why Hardware-Optimized Builds?

Upstream Vector distributes generic pre-compiled binaries targeting baseline CPU specifications (`x86-64` baseline and `aarch64` ARMv8.0-A) to guarantee compatibility with older processors. However, modern cloud instances (AWS Graviton, GCP Tau T2A, AMD EPYC, Intel Xeon) feature advanced architectural extensions that deliver substantial latency and throughput gains:

### 1. ARM64 Cloud Servers (`aarch64-unknown-linux-gnu-lse`)
* **Inlined ARM Large System Extensions (`+lse`)**: Replaces runtime trampoline helper calls (`__aarch64_cas8_acq_rel`) and load-linked / store-conditional (`ldxr`/`stxr`) retry loops with inlined single-instruction atomic operations (`ldadd`, `cas`, `swp`).
* **Lower Processing Latency**: Eliminates subroutine call frame setup and register spilling for every atomic operation across Tokio worker threads, channel buffers, and metric counters.
* **Reduced Multi-Thread Contention in Sinks**: Accelerates high-frequency reference counting and queue synchronization inside multi-threaded sinks (e.g. `rdkafka` / `librdkafka`), lowering tail latency and preventing queue-full backpressure.
* **Neoverse-N1 Microarchitecture Tuning**: Optimizes instruction scheduling, loop alignments, and branch prediction specifically for modern ARM server cores.
* **Target Platforms**: AWS Graviton 2/3/4, Google Cloud Tau T2A, Ampere Altra, Azure Cobalt 100.

### 2. Modern x86_64 Cloud Servers (`x86_64-unknown-linux-gnu-v3`)
* **x86-64 Microarchitecture Level 3 (`x86-64-v3`)**: Unlocks AVX, AVX2, FMA, BMI1, BMI2, F16C, and LZCNT instructions.
* **Accelerated Event Throughput**: Leverages 256-bit SIMD registers for high-speed string scanning, UTF-8 validation (`simdutf8`), base64 encoding (`base64-simd`), and state machine lookups.
* **Faster Compression**: Unlocks AVX2 vector fast-paths in compression codecs (`zstd`, `lz4`, `gzip`), reducing CPU saturation when sending compressed batches to storage and logging sinks.
* **Low-Latency Bit Manipulation**: Utilizes single-cycle bit-manipulation instructions (`BMI2`, `LZCNT`) for rapid bitmask evaluation, hashing, and framing decoders.
* **Target Platforms**: Modern Intel Xeon (Haswell+) and AMD EPYC (Zen 1+) cloud VMs.

---

## Measured Performance Gains (Neoverse-N1 / Ampere Altra)

Empirically validated on Google Cloud Compute Engine (`t2a-standard-16`, 16 vCPUs Neoverse-N1, 64 GB RAM) processing 500,000 JSON log events through a realistic `demo_logs` $\rightarrow$ `remap` (VRL parsing & enrichments) $\rightarrow$ `blackhole` pipeline:

### End-to-End Pipeline Throughput & Latency

| Metric | Upstream Generic (`aarch64`) | Hardware-Optimized (`+lse`) | Improvement |
|:---|:---:|:---:|:---:|
| **Pipeline Throughput** | 58,378 events/sec | **61,171 events/sec** | **+4.78% higher throughput** |
| **Batch Processing Wall Time** | 8.565 s | **8.174 s** | **−4.57% lower latency** |
| **Release Binary Size** | 37.68 MB | **36.16 MB** | **−1.53 MB smaller (−4.06%)** |

### Microbenchmark Latency & Contention Metrics

| Workload | Concurrency | Upstream Baseline | Hardware-Optimized (`+lse`) | Performance Gain |
|:---|:---:|:---:|:---:|:---:|
| **Atomic Counter (`fetch_add_u64`)** | 1 thread | 95.46 µs (104.75 Melem/s) | **89.87 µs (111.27 Melem/s)** | **+6.12% throughput (−5.8% latency)** |
| **Atomic Counter (`fetch_add_u64`)** | 4 threads | 443.8 µs (90.13 Melem/s) | **406.4 µs (98.42 Melem/s)** | **+9.08% throughput (−8.4% latency)** |
| **Float CAS Loop (`fetch_update_f64`)** | 2 threads | 506.9 µs (39.45 Melem/s) | **454.6 µs (44.00 Melem/s)** | **+11.65% throughput (−10.3% latency)** |
| **Float CAS Loop (`fetch_update_f64`)** | 4 threads | 1.51 ms (26.50 Melem/s) | **1.30 ms (30.79 Melem/s)** | **+14.50% throughput (−13.9% latency)** |
| **Histogram Record (`Histogram::record`)** | 1 thread | 169.3 µs (29.53 Melem/s) | **145.5 µs (34.37 Melem/s)** | **+17.29% throughput (−14.1% latency)** |

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

### For Modern x86_64 Servers (Intel Xeon Haswell+, AMD EPYC Zen+)
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
1. **Upstream Release Detection**: A scheduled GitHub Actions workflow runs daily at 02:00 UTC to inspect [vectordotdev/vector](https://github.com/vectordotdev/vector) for new official releases.
2. **Dedicated Runner Compilation**:
   - **x86_64 Builds**: Run locally on a Kubernetes ARC runner scale set (`runs-on: arc-runner-set`) targeting `x86-64-v3`.
   - **ARM64 Builds**: Dynamically provision an ephemeral Google Cloud `t2a-standard-16` instance (16 Neoverse-N1 cores), compile with native LSE and CFLAGS, and automatically terminate the VM upon completion.
3. **Artifact Publishing**: Packages stripped binaries, default configuration templates, and systemd units into `.tar.gz` archives, calculates SHA256 checksums, and attaches them to GitHub Releases.

---

## License

This project packages official releases of [Vector](https://github.com/vectordotdev/vector). Vector is licensed under the [Mozilla Public License 2.0 (MPL-2.0)](https://www.mozilla.org/en-US/MPL/2.0/) or [Apache-2.0](LICENSE).
