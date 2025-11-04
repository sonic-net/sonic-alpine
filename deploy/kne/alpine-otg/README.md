# twodut-alpine-otg

Two-DUT Alpine topology with Open Traffic Generator (OTG) for network testing and validation.

## Overview

This project provides a KNE-based topology with two Alpine switches (DUT and CTL) and an OTG controller with traffic engines for comprehensive network testing, including:
- Traffic benchmarking across multiple port pairs
- Network impairment testing (loss, delay, jitter)

## Prerequisites

- KVM-enabled workstation or VM
- Docker installed and running
- kubectl configured
- KNE (Kubernetes Network Emulator) installed

## Build

Follow the Alpine build instructions: https://github.com/sonic-net/sonic-alpine/blob/master/README.md

## Installation

A KVM enabled workstation (or VM) that can support VMs on it

1. [Download and install KNE](https://github.com/openconfig/kne). Setup KNE cluster
```
kne deploy deploy/kne/kind-bridge.yaml
```

2. Load alpinevs container image in KNE
```
kind load docker-image alpine-vs:latest --name kne
```

3. Download [Lemming](https://github.com/openconfig/lemming). Build the Lucius dataplane and load it
```
gh repo clone openconfig/lemming
cd lemming
bazel build //dataplane/standalone/lucius:image-tar
docker load -i bazel-bin/dataplane/standalone/lucius/image-tar/tarball.tar
kind load docker-image us-west1-docker.pkg.dev/openconfig-lemming/release/lucius:ga --name kne

```

4.  Pull and Load KENG Controller

```bash
# Pull the controller image
docker pull ghcr.io/open-traffic-generator/keng-controller:1.14.0-1

# Load into KNE cluster
kind load docker-image ghcr.io/open-traffic-generator/keng-controller:1.14.0-1 --name kne
```

5. Pull and Load Ixia-c Traffic Engine

```bash
# Pull the traffic engine image
docker pull ghcr.io/open-traffic-generator/ixia-c-traffic-engine:1.8.0.99

# Load into KNE cluster
kind load docker-image ghcr.io/open-traffic-generator/ixia-c-traffic-engine:1.8.0.99 --name kne
```

6. Install otgen CLI (optional but recommended)

```bash
# Install otgen for traffic generation
go install github.com/open-traffic-generator/otgen@latest

# Or download from releases:
# https://github.com/open-traffic-generator/otgen/releases
```


## Installation

### 1. Create Topology

Edit `twodut-alpine-otg.textproto` to ensure image references match your loaded images:

```protobuf
# Update these lines to match your environment:
# - Alpine image: alpine-vs:latest
# - Lucius image: us-west1-docker.pkg.dev/openconfig-lemming/release/lucius:ga
```

Create the topology:

```bash
kne create twodut-alpine-otg.textproto
```

### 2. Verify Deployment

```bash
# Check namespace and pods
kubectl get pods -n twodut-alpine-otg

# Expected output should show:
# - alpine-dut
# - alpine-ctl
# - otg-controller
# - otg-port-eth1, otg-port-eth2, otg-port-eth3, otg-port-eth4
```

### 3. Initialize Environment

```bash
cd scripts/
./reset_cluster.sh
```

This will:
- Wire L2 bridges (br100) on both switches
- Enable STP to prevent loops
- Discover the OTG controller API endpoint
- Write configuration to `../.env`

Load the environment:
```bash
source ../.env
echo $OTG_API  # Should show https://<IP>:8443
```

## Usage

### Quick Start - Smoke Test

Run a complete end-to-end test:

```bash
cd scripts/
./smoke_test.sh
```

This will:
1. Run preflight configuration checks
2. Execute baseline traffic tests on both port pairs
3. Apply network impairments and re-test
4. Generate reports with charts
5. Restore clean state

### Individual Test Scripts

#### Configuration Check
```bash
./configuration.sh
# Validates: namespace, controller, pods, L2 wiring, basic probes
```

#### Conformance Testing
```bash
./conformance.sh
# Tests: namespace, controller reachability, traffic engines, bridge config, flow probes
```

#### Benchmarking
```bash
# Run with defaults (10k packets per test)
./bench.sh

# Run with custom packet count
PKTS=50000 ./bench.sh

# View results
./report.sh
```

#### Network Impairment Testing
```bash
# Turn on impairment
IMP_LOSS=1 IMP_DELAY=10ms IMP_JITTER=2ms ./impair_on.sh

./bench.sh

# Turn off impairment
./impair_off.sh
```

#### A/B Comparison (Baseline vs Impaired)
```bash
# Full A/B test
IMP_LOSS=0.5 IMP_DELAY=5ms IMP_JITTER=1ms ./compare.sh

# skip baseline if already done
SKIP_BASELINE=1 ./compare.sh
```

#### Scale Testing
```bash
# Multi-port bidirectional testing
PORT_PAIRS="eth1,eth2;eth3,eth4" BIDIR=1 PPS=10000 ./scale_matrix.sh
```

#### Natural Language DSL
```bash
# Use natural language to describe test scenarios
./nl_run.py "baseline on eth1,eth2 bidir at 20kpps size 512 count 50000;
             impaired on eth1,eth2 loss 0.5% delay 5ms jitter 1ms bidir at 40kpps"
```

#### Complete Test Suite
```bash
# Run everything 
./smoke_all.sh
```

## Configuration 


The scripts automatically do this but for manual changes. 

### Environment Variables

Create or edit `../.env`:

```bash
export OTG_API="https://10.x.x.x:8443"
export OTG_LOCATION_P1="eth1"
export OTG_LOCATION_P2="eth2"
export OTG_LOCATION_P3="eth3"
export OTG_LOCATION_P4="eth4"
```

### Test Parameters

Common overrides for test scripts:

```bash
# Traffic parameters
export PPS=20000          # Packets per second
export PKTS=10000         # Packets per flow
export PKTSIZE=512        # Packet size (bytes)

# Impairment parameters
export IMP_LOSS=0.5       # Loss percentage
export IMP_DELAY=5ms      # Delay
export IMP_JITTER=1ms     # Jitter

# Host interfaces for impairment
export IFACES="eth13 eth14 eth15 eth16"

# Kubernetes
export NS=twodut-alpine-otg
export DUT_POD=alpine-dut
export CTL_POD=alpine-ctl
```

## Output and Reports

All results are stored in `../results/`:

```
results/
├── runs/                        # CSV files with raw data
│   ├── bench_YYYYMMDD_HHMMSS.csv
│   ├── scale_YYYYMMDD_HHMMSS.csv
│   └── ...
├── charts/                      # Generated charts
│   ├── loss_vs_pps.png
│   └── best_safe_pps.png
├── report_YYYYMMDD_HHMMSS.md   # Markdown reports with analysis
├── configuration_*.md           # Preflight check results
├── conformance_*.md            # Conformance test results
├── compare_*.md                # A/B comparison summaries
└── report_before_*.md          # Baseline snapshots
└── report_after_*.md           # Post-impairment snapshots
```

## Troubleshooting

### Controller Not Reachable

```bash
# Check controller service
kubectl get svc -n twodut-alpine-otg service-https-otg-controller

# Check controller pod
kubectl get pods -n twodut-alpine-otg | grep controller
kubectl logs -n twodut-alpine-otg <controller-pod>

# Verify LoadBalancer IP assigned
kubectl get svc -n twodut-alpine-otg service-https-otg-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

### Traffic Engines Not Ready

```bash
# Check all pods in the namespace
kubectl get pods -n twodut-alpine-otg

# Check specific traffic engine logs
kubectl logs -n twodut-alpine-otg otg-port-eth1 -c ixia-c-port
```

### Bridge Configuration Issues

```bash
# Check DUT bridge
kubectl exec -n twodut-alpine-otg alpine-dut -c dataplane -- bridge link

# Check CTL bridge
kubectl exec -n twodut-alpine-otg alpine-ctl -c dataplane -- bridge link

# Repair bridges
./configuration.sh
```

### High Packet Loss

1. Verify bridge configuration: `./configuration.sh`
2. Check impairment is off: `./impair_off.sh`
3. Verify STP is enabled (done by `reset_cluster.sh`)
4. Check for traffic loops in dataplane logs
5. Reduce PPS or packet count
6. Verify port mappings match topology

### Access Switches

```bash
# DUT switch
export IPDUT=$(kubectl get svc service-alpine-dut -n twodut-alpine-otg -o jsonpath='{.status.loadBalancer.ingress[*].ip}')
ssh -i /tmp/id_rsa admin@$IPDUT

# CTL switch
export IPCTL=$(kubectl get svc service-alpine-ctl -n twodut-alpine-otg -o jsonpath='{.status.loadBalancer.ingress[*].ip}')
ssh -i /tmp/id_rsa admin@$IPCTL

# Or directly via kubectl
kubectl exec -it -n twodut-alpine-otg alpine-dut -c dataplane -- bash
```


## Performance Tips

- **Reduce PKTS** for faster iteration: `PKTS=5000 ./bench.sh`
- **Increase PPS** for stress testing: `PPS=100000 ./bench.sh`
- **Parallel execution**: scale_matrix.sh uses `CONC` parameter
- **Reuse baseline**: `SKIP_BASELINE=1 ./compare.sh`

## References

- [Open Traffic Generator](https://github.com/open-traffic-generator)
- [KENG Controller](https://github.com/open-traffic-generator/keng-controller)
- [Ixia-c Traffic Engine](https://github.com/open-traffic-generator/ixia-c)
- [KNE](https://github.com/openconfig/kne)
- [SONiC Alpine](https://github.com/sonic-net/sonic-alpine)
- [Lemming](https://github.com/openconfig/lemming)




