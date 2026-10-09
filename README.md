*Alpine builds*: [![Alpine](https://dev.azure.com/mssonic/build/_apis/build/status/3412?branchName=master&label=master)](https://dev.azure.com/mssonic/build/_build/latest?definitionId=3412&branchName=master) 
  [![Alpine](https://dev.azure.com/mssonic/build/_apis/build/status/3412?branchName=202605&label=202605)](https://dev.azure.com/mssonic/build/_build/latest?definitionId=3412&branchName=202605)

## Instructions

## Documentation
The High Level Design document of Alpine can be found [here](https://github.com/sonic-net/SONiC/blob/master/doc/alpine/alpine_hld.md).

There are two flavours of Alpine. The Alpine Virtual Switch (AVS or ALViS) is made up of two containers - the Switchstack Container that runs the SONiC VM and an ASIC Simulation Container that runs the virtual ASIC. The SwitchStack Container hosts a VM on which the SONiC components run in their own contaniers.

The Alpine Virtual Switch-lite (AVS-lite) is a lightweight version of the AVS. It runs on a single container in which the SONiC components run as processes. The virtual ASIC also runs as a process.

## Alpine Virtual Switch

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
SONIC_BUILD_JOBS=8 make target/sonic-alpinevs.img.gz
```

6. Load the alpinevs container
```
docker load -i target/sonic-alpinevs-docker.tar.gz
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

3. Download [Lemming](https://github.com/openconfig/lemming)

Install the [dependencies](https://github.com/openconfig/lemming/blob/main/README.md), build the Lucius dataplane and load it

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
The password is set in your [sonic-buildimage/rules/config](https://github.com/sonic-net/sonic-buildimage/blob/737879a82577bb2f102fd6de98cb4f708a6da177/rules/config#L78).  The default password is YourPaSsWoRd . You may want to change it to something easier.

5. Useful commands

- Login to the host

```
kubectl exec -it -n twodut-alpine alpine-dut -- bash
```

- Dataplane logs
```
kubectl logs -n twodut-alpine alpine-dut -c dataplane
```

### Download the AlpineVS image 

You can obtain the AlpineVS image in one of the following ways:

1. **Run the download script**

On a Linux system, run the [image download script](https://github.com/sonic-net/sonic-alpine/blob/master/utils/get_official_build.sh)
```
sudo apt install jq (if not already present)
get_official_build.sh
```

2. **Download the official image**

Download from the [AlpineVS official build](https://sonic-build.azurewebsites.net/ui/sonic/pipelines/3412/builds?branchName=master) or the [sonic-buildimage official build](https://sonic-build.azurewebsites.net/ui/sonic/pipelines/1/builds?branchName=master)

#### Extract and load the image

Extract the downloaded image archive and load the image into the Docker and KNE cluster:
```
docker load -i target/sonic-alpinevs-docker.tar.gz
kind load docker-image alpine-vs:latest --name kne
```
Then follow the steps in the [Deploy](#deploy) section

## Alpine Virtual Switch-lite (AVS-lite)

Follow the steps 1 to 4 to [clone and configure](#build) AlpineVS.

1. Build

SONIC_BUILD_JOBS specifies the number of build tasks that run parallely. An ideal number depends on the resources but a value of 8 or 16 is reasonable for most systems.

```
SONIC_BUILD_JOBS=8 make target/docker-sonic-alpinevs.gz
```

2. Load the alpinevs container
```
docker load -i target/docker-sonic-alpinevs.gz
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

Unlike AVS, AVS-lite does not need separate installation of Lemming.

4. Create the two switch Alpine topology:

- Open the [twodut-single-docker-alpinevs.txt](https://github.com/sonic-net/sonic-alpine/blob/master/src/deploy/kne/twodut-single-docker-alpinevs.txt) file. Note that this is not the same topolgy file used for AVS. Ensure that it points to the correct Alpine image name. You can find the name of the images from the output of 'docker images -a'. For example,

```
docker images -a | grep alpine
alpine-vs:latest                                               ebd8a4a5b357      5.04GB      0B
```

- Create the KNE topology
```
kne create twodut-single-docker-alpinevs.txt
```
Confirm that the alpine-ctl and alpine-dut are in running state.
```
kubectl get pods -A | grep alpine
docker-twodut-alpine   docker-alpine-ctl   1/1  Running  0  3m10s
docker-twodut-alpine   docker-alpine-dut   1/1  Running  0  3m10s

```

5. Terminals

You can set up the SSH as described in the 'terminals' section under [deploy](#deploy) but with slightly different namespace and service names.

```
kubectl get svc -n docker-twodut-alpine service-docker-alpine-dut
NAME                        TYPE           CLUSTER-IP      EXTERNAL-IP    PORT(S)                    AGE
service-docker-alpine-dut   LoadBalancer   10.96.146.208   192.168.8.50   22/TCP,9339/TCP,9559/TCP   7m50s

kubectl get svc -n docker-twodut-alpine service-docker-alpine-ctl
NAME                        TYPE           CLUSTER-IP     EXTERNAL-IP    PORT(S)                    AGE
service-docker-alpine-ctl   LoadBalancer   10.96.104.18   192.168.8.51   22/TCP,9339/TCP,9559/TCP   7m54s
```

Or more easily, get the external ip addresses directly from kubectl as above and insert them in the ssh command
```
ssh admin@a.b.c.d -o ProxyCommand=none -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o PubkeyAuthentication=no
```

The password is set in your [sonic-buildimage/rules/config](https://github.com/sonic-net/sonic-buildimage/blob/737879a82577bb2f102fd6de98cb4f708a6da177/rules/config#L78). The default password is YourPaSsWoRd.


