## Instructions

### Documentation
The High Level Design document of Alpine can be found [here](https://github.com/sonic-net/SONiC/blob/master/doc/alpine/alpine_hld.md).

### Build
1. Clone the SONiC repo:
```
git clone https://github.com/sonic-net/sonic-buildimage.git
```

2. Init
```
export NOJESSIE=1 NOSTRETCH=1 NOBUSTER=1 NOBULLSEYE=1 NOBOOKWORM=0 NOTRIXIE=0
cd sonic-buildimage
make init
```

3. Enable build for modules of interest

These are optional modules that are not necessary for the base Alpine.

#### GNMI
```
echo "INCLUDE_SYSTEM_GNMI = y" >> rules/config.user
echo "ENABLE_TRANSLIB_WRITE = y" >> rules/config.user
```

#### P4RT
```
echo "INCLUDE_P4RT = y" >> rules/config.user
```

Pull the latest version of the sonic-pins

```
git submodule update --remote src/sonic-p4rt/sonic-pins
```

4. Configure
```
PLATFORM=alpinevs make configure
```

5. Build

SONIC_BUILD_JOBS specifies the number of build tasks that run parallely. An ideal number depends on the resources but a value of 8 or 16 is reasonable for most systems.

```
SONIC_BUILD_JOBS=16 make target/sonic-alpinevs.img.gz
```

6. Build alpinevs container
```
platform/alpinevs/src/build/build_alpinevs_container.sh
```

### Deploy
Pre-requisite:
A KVM enabled workstation (or VM) that can support VMs on it

1. [Download and install KNE](https://github.com/openconfig/kne). 

Setup KNE cluster

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
bazel clean --expunge
bazel build  --output_groups=+tarball //dataplane/standalone/lucius:image-tar
docker load -i bazel-bin/dataplane/standalone/lucius/image-tar/tarball.tar
kind load docker-image us-west1-docker.pkg.dev/openconfig-lemming/release/lucius:ga --name kne

```

4. Create the two switch Alpine topology:

- Open the [twodut-alpine-vs.pb.txt](https://github.com/sonic-net/sonic-alpine/blob/master/src/deploy/kne/twodut-alpine-vs.pb.txt) file and ensure that it points to the correct Alpine and Lucius images. You can find the name of the images from the output of 'docker images -a'. For example,
```
docker images -a | grep lucius
us-west1-docker.pkg.dev/openconfig-lemming/release/lucius:ga   01b58c448eaf       217MB      0B

docker images -a | grep alpine
alpine-vs:latest                                               ebd8a4a5b357      5.04GB      0B
```

- Create the KNE topology
```
kne create twodut-alpine-vs.pb.txt
```
Confirm that the alpine-ctl and alpine-dut are in running state.
```
kubectl get pods -A | grep alpine
twodut-alpine    alpine-ctl    2/2     Running   0    16h
twodut-alpine    alpine-dut    2/2     Running   0    16h

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

Alternately, you can get the external ip addresses directly from kubectl and insert them in the ssh command
```
kubectl get services -A | grep alpine
twodut-alpine   service-alpine-ctl    LoadBalancer   10.96.215.178   192.168.8.51   22/TCP,9339/TCP,9559/TCP   16h
twodut-alpine   service-alpine-dut    LoadBalancer   10.96.195.3     192.168.8.50   22/TCP,9339/TCP,9559/TCP   16h

ssh admin@a.b.c.d -o ProxyCommand=none -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o PubkeyAuthentication=no
```
The password is set in your [sonic-buildimage/rules/config](https://github.com/sonic-net/sonic-buildimage/blob/737879a82577bb2f102fd6de98cb4f708a6da177/rules/config#L78). You may want to change it to something simpler.

5. Useful commands

- Login to the host

```
kubectl exec -it -n twodut-alpine alpine-dut -- bash
```

- Dataplane logs
```
kubectl logs -n twodut-alpine alpine-dut -c dataplane
```

