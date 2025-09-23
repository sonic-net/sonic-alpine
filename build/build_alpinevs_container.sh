gzip -d target/sonic-alpinevs.img.gz
mv target/sonic-alpinevs.img src/sonic-alpine/deploy/kne/vm/vm.img
docker build src/sonic-alpine/deploy/kne/vm -t alpine-vs:latest
