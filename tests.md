

This document describes the steps for running the Ondatra/Thinkit tests with two AlpineVS switches connected in a mirror topology. Refer the [Alpine deployment](https://github.com/sonic-net/sonic-alpine/blob/master/README.md#deploy) for the configuration details. [SONiC-Ondatra Test Framework](https://github.com/sonic-net/sonic-mgmt/tree/master/sdn_tests) has more on Ondatra. 


### Preparing the sonic-mgmt repo

Clone sonic-mgmt repo
```
gh repo clone sonic-net/sonic-mgmt
```

Set up the sonic management docker
```
./setup-container.sh  -n docker-sonic-mgmt-test -d /data
```

Set up the docker network connection between the kne docker that runs alpine and the sonic-mgmt docker
```
docker network connect kind docker-sonic-mgmt-test
```

Login into the docker
```
docker exec --user admin -ti docker-sonic-mgmt-test bash
cd /data/sonic-mgmt
```

Download bazel-6.4.0-installer-linux-x86_64.sh and install inside the docker
```
wget https://github.com/bazelbuild/bazel/releases/download/6.4.0/bazel-6.4.0-installer-linux-x86_64.sh
sudo apt update
sudo apt-get install unzip
sudo ./bazel-6.4.0-installer-linux-x86_64.sh
```

ssh into the CTL/DUT from inside the sonic-mgmt docker to confirm that the CTL/DUT are reachable. The IP addresses can be obtained from ‘kubectl get services’, please refer [Alpine Readme](https://github.com/sonic-net/sonic-alpine/blob/master/README.md#deploy)

### Configuring the test environment

The IP addresses of the DUT and the CTL switch (obtained above) have to be manually updated in the [ReserveTopology](https://github.com/sonic-net/sonic-mgmt/blob/d513d50bf66febb880fb626b714cc676b543f11a/sdn_tests/pins_ondatra/infrastructure/binding/pins_backend.go#L80)

### Arbitration test

To run the test, the [middleblock.p4info.pb.txt](https://github.com/sonic-net/sonic-pins/blob/main/sai_p4/instantiations/google/middleblock.p4info.pb.txt) must be available. This example assumes that it is copied into the /data/sonic-mgmt directory

From inside the sonic-mgmt docker, run the test with the following arguments

```
cd /data/sonic-mgmt/sdn_tests/pins_ondatra

bazel test //tests/thinkit:arbitration_test --define=absl=1 --test_strategy=standalone --test_arg=--gnmi_deviceid_support=false --test_arg=--gnmi_push_support=false --test_arg=--gnmi_boottime_support=false --test_arg=--gnmi_state_and_config_support=false --test_output=streamed  --test_arg=--pins_p4info_file="/data/sonic-mgmt/middleblock.p4info.pb.txt"
```

All going well, you should see the tests pass ! 

```
[----------] 14 tests from pinsArbitrationTest/ArbitrationTestFixture (48934 ms total)

[----------] Global test environment tear-down
[==========] 14 tests from 1 test suite ran. (48934 ms total)
[  PASSED  ] 14 tests.
Target //tests/thinkit:arbitration_test up-to-date:
  bazel-bin/tests/thinkit/arbitration_test
INFO: Elapsed time: 49.579s, Critical Path: 49.20s
INFO: 2 processes: 1 internal, 1 local.
INFO: Build completed successfully, 2 total actions
//tests/thinkit:arbitration_test PASSED in 49.1s

Executed 1 out of 1 test: 1 test passes.
```

