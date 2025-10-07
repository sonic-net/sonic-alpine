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
Include these modules if required

```
echo "# Updates for Alpine" > rules/config.user
echo "INCLUDE_SYSTEM_GNMI = y" >> rules/config.user
echo "ENABLE_TRANSLIB_WRITE = y" >> rules/config.user
```
3. Configure
```
PLATFORM=alpinevs make configure
```
4. Build
```
make target/sonic-alpinevs.img.gz
```
5. Build alpinevs container
```
./alpine/build_alpinevs_container.sh
```
### Deploy

Pre-req:
A KVM enabled workstation (or VM) which can support VMs on it

1. Install KNE and setup KNE cluster
```
kne deploy deploy/kne/kind-bridge.yaml
```
2. Load alpinevs container image in kne:
```
kind load docker-image alpine-vs:latest --name kne
```
3. Download Lemming. Build the Lucius dataplane and load it
```
https://github.com/openconfig/lemming
cd lemming
bazel build //dataplane/standalone/lucius:image-tar
docker load -i bazel-bin/dataplane/standalone/lucius/image-tar/tarball.tar
kind load docker-image us-west1-docker.pkg.dev/openconfig-lemming/release/lucius:ga --name kne

```
4. Create 2 switch Alpine topology:

- Modify the deploy/kne/twodut-alpine.pb.txt to point to the correct Alpine and Lucius images
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

