gzip -d -c target/sonic-alpinevs.img.gz > platform/alpinevs/src/deploy/kne/vm/vm.img
sudo service docker status > /dev/null 2>&1 || (sudo service docker start > /dev/null 2>&1 && ./scripts/wait_for_docker.sh 60)
DOCKER_BUILDKIT=0 docker build platform/alpinevs/src/deploy/kne/vm -t alpine-vs:latest
docker save alpine-vs:latest | gzip -c > target/sonic-alpinevs-docker.tar.gz
