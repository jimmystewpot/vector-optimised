# Vector (Hardware-Optimized Builds)

[![Daily Release Check](https://github.com/jimmystewpot/vector-optimised/actions/workflows/release.yml/badge.svg)](https://github.com/jimmystewpot/vector-optimised/actions/workflows/release.yml)
[![GitHub Release](https://img.shields.io/github/v/release/jimmystewpot/vector-optimised?include_prereleases&style=flat-square)](https://github.com/jimmystewpot/vector-optimised/releases)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

High-performance, automated, hardware-optimized distributions of [Vector](https://github.com/vectordotdev/vector) engineered for **maximum throughput**, **lower end-to-end latency**, and **reduced CPU overhead** on modern cloud server architectures.

---

## Why Hardware-Optimized Builds?

Upstream Vector distributes generic pre-compiled binaries targeting baseline CPU specifications (`x86-64` baseline and `aarch64` ARMv8.0-A) to guarantee compatibility with older processors. However, modern cloud instances (AWS Graviton, GCP Tau T2A, AMD EPYC, Intel Xeon) feature advanced architectural extensions that deliver substantial latency and throughput gains:

### 1. ARM64 Cloud Servers (`aarch64-unknown-linux-gnu-lse`)
* **Compiler Flags & Architecture Tuning**:
  * **C/C++ (`CFLAGS` / `CXXFLAGS`)**: `-O3 -march=armv8.2-a+lse+crc`
  * **Rust (`RUSTFLAGS`)**: `-C target-feature=+lse,+crc -C panic=abort -C link-arg=-Wl,--gc-sections -C link-arg=-Wl,-O3`
* **Modern Build Toolchain**: Built using GCC 14+ on Ubuntu 24.04 LTS alongside the latest stable Rust compiler managed via `rustup`.
* **Inlined ARM Large System Extensions (`+lse`)**: Replaces runtime trampoline helper calls (`__aarch64_cas8_acq_rel`) and load-linked / store-conditional (`ldxr`/`stxr`) retry loops with inlined single-instruction atomic operations (`ldadd`, `cas`, `swp`).
* **Lower Processing Latency**: Eliminates subroutine call frame setup and register spilling for every atomic operation across Tokio worker threads, channel buffers, and metric counters.
* **Hardware CRC32 Acceleration (`+crc`)**: Unlocks dedicated ARM CRC32 instructions for accelerated checksumming in network protocols, framing, and data integrity verification.
* **Reduced Multi-Thread Contention in Sinks**: Accelerates high-frequency reference counting and queue synchronization inside multi-threaded sinks (e.g. `rdkafka` / `librdkafka`), lowering tail latency and preventing queue-full backpressure.
* **Binary Size & Runtime Optimization**:
  * `-C panic=abort`: Removes stack unwinding landing pads and unwinding tables, significantly shrinking binary footprint and improving CPU instruction cache efficiency.
  * `-C link-arg=-Wl,--gc-sections`: Eliminates dead code and unused symbols at link time.
  * `-C link-arg=-Wl,-O3`: Applies aggressive whole-program linker optimizations to optimize final layout and execution paths.
* **Build Architecture (Google Cloud Axion C4A)**: Compiled natively on ephemeral Google Cloud Axion C4A SPOT runners powered by ARM Neoverse-V2 cores.
* **Target Platforms**: Google Cloud Axion (C4A), AWS Graviton 2/3/4, Google Cloud Tau T2A, Ampere Altra / AmpereOne, Azure Cobalt 100.

### 2. Modern x86_64 Cloud Servers (`x86_64-unknown-linux-gnu-v3`)
* **Compiler Flags & Architecture Tuning**:
  * **C/C++ (`CFLAGS` / `CXXFLAGS`)**: `-O3 -march=x86-64-v3`
  * **Rust (`RUSTFLAGS`)**: `-C target-cpu=x86-64-v3 -C panic=abort -C link-arg=-Wl,--gc-sections -C link-arg=-Wl,-O3`
* **Modern Build Toolchain**: Built using GCC 14+ alongside the latest stable Rust compiler managed via `rustup` on Kubernetes Actions Runner Controller (ARC) runners.
* **x86-64 Microarchitecture Level 3 (`x86-64-v3`)**: Unlocks AVX, AVX2, FMA, BMI1, BMI2, F16C, and LZCNT instructions.
* **Accelerated Event Throughput**: Leverages 256-bit SIMD registers for high-speed string scanning, UTF-8 validation (`simdutf8`), base64 encoding (`base64-simd`), and state machine lookups.
* **Faster Compression**: Unlocks AVX2 vector fast-paths in compression codecs (`zstd`, `lz4`, `gzip`), reducing CPU saturation when sending compressed batches to storage and logging sinks.
* **Low-Latency Bit Manipulation**: Utilizes single-cycle bit-manipulation instructions (`BMI2`, `LZCNT`) for rapid bitmask evaluation, hashing, and framing decoders.
* **Binary Size & Runtime Optimization**:
  * `-C panic=abort`: Removes stack unwinding landing pads and unwinding tables, significantly shrinking binary footprint and improving CPU instruction cache efficiency.
  * `-C link-arg=-Wl,--gc-sections`: Eliminates dead code and unused symbols at link time.
  * `-C link-arg=-Wl,-O3`: Applies aggressive whole-program linker optimizations to optimize final layout and execution paths.
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

## Measured Performance Gains (x86_64-v3 / AVX2 / AMD Zen & Intel Xeon)

Empirically validated on modern AMD Zen architecture (`AMD Ryzen AI 9 HX 370`, 12 cores / 24 threads, AVX2, AVX-512, BMI2, SSE4.2) comparing generic upstream `x86-64` against `x86-64-v3` compiled builds with identical release optimization profiles (`opt-level = 3`, `lto = "fat"`, `codegen-units = 1`):

### Compression & Decompression Throughput & Latency (Realistic JSON Log Payloads)

| Codec / Workload | Operation | Payload Size | Upstream Generic (`x86-64`) | Hardware-Optimized (`x86-64-v3`) | Performance Gain |
|:---|:---:|:---:|:---:|:---:|:---:|
| **Gzip (Default Compression)** | Compress | 4 MB | 729.96 µs (5.35 GB/s) | **671.26 µs (5.82 GB/s)** | **+8.74% throughput (−8.04% latency)** |
| **Gzip (Default Compression)** | Compress | 1 MB | 183.01 µs (5.34 GB/s) | **179.43 µs (5.44 GB/s)** | **+2.00% throughput (−1.96% latency)** |
| **Zstandard (Level 3)** | Decompress | 64 KB | 3.64 µs (16.76 GB/s) | **3.40 µs (17.95 GB/s)** | **+7.12% throughput (−6.64% latency)** |
| **Zstandard (Level 3)** | Compress | 64 KB | 10.91 µs (5.59 GB/s) | **10.39 µs (5.87 GB/s)** | **+4.99% throughput (−4.75% latency)** |
| **Zstandard (Level 3)** | Compress | 1 MB | 105.46 µs (9.26 GB/s) | 111.60 µs (8.75 GB/s) | Parity (C library runtime dispatch) |
| **Snappy (Raw Block)** | Decompress | 4 MB | 167.02 µs (23.39 GB/s) | 174.67 µs (22.36 GB/s) | Parity (−4.38% throughput) |
| **Snappy (Framed Stream)** | Decompress | 1 MB | 134.36 µs (7.27 GB/s) | 138.25 µs (7.06 GB/s) | Parity (−2.81% throughput) |
| **Snappy (Framed Stream)** | Compress | 64 KB | 8.27 µs (7.38 GB/s) | 8.52 µs (7.17 GB/s) | Parity (−2.96% throughput) |
| **LZ4 (Block, pure-Rust)** | Compress | 4 MB | 113.85 µs (34.31 GB/s) | 132.21 µs (29.55 GB/s) | −13.89% throughput |

* **Analysis & Codec Characteristics**:
  * **Streaming / Deflate (Gzip)**: Leverages 256-bit AVX2 vectorization and BMI2 bit manipulation for hash chain traversal, LZ77 sliding window matching, and Huffman bitstream emission, delivering **+8.74% higher throughput** and **−8.04% lower latency** on large batches.
  * **Zstandard**: Shows immediate throughput gains on small payload blocks (**+7.12% decompression, +4.99% compression**), while multi-megabyte payloads remain at parity due to libzstd's internal runtime CPU feature selection.
  * **Pure-Rust Byte Loops (`snap` / `lz4_flex`)**: Generic `x86-64` compiles to highly tuned scalar 64-bit word unaligned copy loops. While `x86-64-v3` introduces 15× more vectorized YMM instructions across the binary (16,714 vs 1,122 instructions), short repeat sequences in pure-Rust LZ4 block codecs can incur loop remainder/peeling overhead.

---

## Additional Codebase Areas Benefiting from Compiler Optimization

In addition to compression codecs, Vector's architecture leverages compiler-optimized extensions across several core subsystems:

1. **Vector Remap Language (VRL) & String Operations**:
   * **`simdutf8`**: Validates UTF-8 strings at multi-gigabyte-per-second throughput using 256-bit AVX2 vectors during log ingestion and VRL parsing.
   * **`base64-simd`**: Accelerated base64 encoding and decoding (`encode_base64`, `decode_base64`) using vector register lookups.
   * **`memchr`**: AVX2-accelerated substring search and byte delimiter scanning across VRL parsing functions.
2. **Columnar Ingestion & Analytical Formats**:
   * **Apache Arrow & Parquet (`parquet`, `arrow-ipc`)**: Unlocks vectorized bitmask evaluation, null bitmap filtering, and dictionary decoders for analytical sinks and file sources.
3. **Topology Routing & Hashing**:
   * **`ahash`**: Directly utilizes hardware AES-NI instructions (`vaesenc`) and folded 64-bit multiplications for single-cycle hashing across internal channel buffers and deduplication caches.
4. **JSON Parsing & Bit Manipulation**:
   * Utilizes BMI2 instructions (`pext`, `pdep`, `lzcnt`, `tzcnt`) for single-cycle bitmask manipulation and rapid escape sequence scanning.

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
   - **ARM64 Builds**: Dynamically provision an ephemeral Google Cloud Axion C4A (`c4a-standard-16`, 16 vCPUs, 64 GB RAM) SPOT runner in `europe-north1-a` (ARM Neoverse-V2 cores) running containerized Ubuntu 24.04 with GCC 14, compile with `-march=armv8.2-a+lse+crc`, and automatically terminate the VM upon completion.
3. **Artifact Publishing**: Packages stripped binaries, default configuration templates, and systemd units into `.tar.gz` archives, calculates SHA256 checksums, and attaches them to GitHub Releases.

---

## License

This project packages official releases of [Vector](https://github.com/vectordotdev/vector). Vector is licensed under the [Mozilla Public License 2.0 (MPL-2.0)](https://www.mozilla.org/en-US/MPL/2.0/) or [Apache-2.0](LICENSE).
