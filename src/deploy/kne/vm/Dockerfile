FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update -qy \
 && apt-get install -qy --no-install-recommends software-properties-common \
 && add-apt-repository -y universe \
 && apt-get update -qy \
 && apt-get install -y \
    bridge-utils \
    iproute2 \
    socat \
    qemu-kvm \
    tcpdump \
    inetutils-ping \
    dnsutils \
    iptables \
    vim \
    wget \
    uml-utilities \
    isc-dhcp-client \
    dnsmasq \
 && rm -rf /var/lib/apt/lists/*

RUN wget https://go.dev/dl/go1.25.9.linux-amd64.tar.gz
RUN tar -C /usr/local -xzf go1.25.9.linux-amd64.tar.gz
ENV PATH="${PATH}:/usr/local/go/bin"

COPY vm.img /vm.img
COPY go.* /
RUN go mod download
COPY *.go /

EXPOSE 22
CMD [ "go" "run" "/main.go" ] 
