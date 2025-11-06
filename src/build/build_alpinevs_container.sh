gzip -d target/sonic-alpinevs.img.gz
mv target/sonic-alpinevs.img platform/alpinevs/src/deploy/kne/vm/vm.img
docker build platform/alpinevs/src/deploy/kne/vm -t alpine-vs:latest
