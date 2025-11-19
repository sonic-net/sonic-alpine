## Instructions

### Build
1. Clone the SONiC repo:
```
git clone https://github.com/sonic-net/sonic-buildimage.git
```

2. Init
```
export NOJESSIE=1 NOSTRETCH=1 NOBUSTER=1 NOBULLSEYE=1
make init
```

3. Enable build for modules of interest
- P4RT
```
echo "INCLUDE_P4RT = y" >> rules/config.user
```
- GNMI
```
echo "INCLUDE_SYSTEM_GNMI = y" >> rules/config.user
echo "ENABLE_TRANSLIB_WRITE = y" >> rules/config.user
```

4. Configure
```
PLATFORM=alpinevs make configure
```

5. Build
```
make target/sonic-alpinevs.img.gz
```

6. Build alpinevs container
```
./alpine/build_alpinevs_container.sh
```

### Deploy
Pre-requisite:
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

4. Create 2 switch Alpine topology:

- Edit the [twodut-alpine.pb.txt](https://github.com/sonic-net/sonic-alpine/blob/master/deploy/kne/twodut-alpine-vs.pb.txt) file to point to the correct Alpine and Lucius images
- Create the KNE topology
```
kne create twodut-alpine.pb.txt
```

5. Terminals

- [Terminal1] SSH to the AlpineVS DUT Switch VM inside the deployment:
```
ssh-keygen -f /tmp/id_rsa -N ""
#Set IPDUT var to the EXTERNAL-IP of "kubectl get svc -n twodut-alpine service-alpine-dut"
export IPDUT=kubectl get svc service-alpine-dut -n twodut-alpine -o jsonpath='{.status.loadBalancer.ingress[*].ip}'
ssh-copy-id -i /tmp/id_rsa.pub -oProxyCommand=none admin@$IPDUT
ssh -i /tmp/id_rsa -oProxyCommand=none admin@$IPDUT
```
- [Terminal2] SSH to the AlpineVS Control Switch VM inside the deployment:
```
ssh-keygen -f /tmp/id_rsa -N ""
#Set IPCTL var to the EXTERNAL-IP of "kubectl get svc -n twodut-alpine service-alpine-ctl"
export IPCTL=kubectl get svc service-alpine-ctl -n twodut-alpine -o jsonpath='{.status.loadBalancer.ingress[*].ip}'
ssh-copy-id -i /tmp/id_rsa.pub -oProxyCommand=none admin@$IPCTL
ssh -i /tmp/id_rsa -oProxyCommand=none admin@$IPCTL
```

5. Useful commands

- Login to the host

```
kubectl exec -it -n twodut-alpine alpine-dut -- bash
```

- Dataplane logs
```
kubectl logs -n twodut-alpine alpine-dut -c dataplane
```

