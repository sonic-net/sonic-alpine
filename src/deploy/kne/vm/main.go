package main

import (
	"flag"
	"fmt"
	"log"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

var (
	configFile = flag.String("config_file", "", "path the config file")
	// TCP port where the SIM pipeline is listening.
	// 50000 is the default port for the Lucius Dataplane pipeline.
	targetPort = flag.Int("target_port", 0, "target port")
)

const (
	waitTimeout = 180 * time.Second
)

// waitForPort waits for the dataplane pipeline to start listening on the specified port.
// It returns an error if the port is not opened within the given timeout.
func waitForPort(port int, timeout time.Duration) {
	deadline := time.Now().Add(timeout)

	for {
		log.Println("Waiting for sim pipeline to listen on port", port)
		conn, err := net.DialTimeout("tcp", fmt.Sprintf(":%d", port), 1*time.Second)
		if err == nil {
			conn.Close()
			return
		}

		if time.Now().After(deadline) {
			log.Fatalf("Timeout: Could not find sim pipeline listening on port %d within %v", port, timeout)
		}

		time.Sleep(1 * time.Second)
	}
}

func main() {
	flag.Parse()
	args := []string{
		"-display", "none", // No display driver
		"-accel", "kvm", // Enable accel
		"-m", "32768", // 32Gi RAM
		"-smp", "12", // 12 CPUs
		"-nographic",                          // Don't launch any windows
		"-drive", "file=/vm.img,format=qcow2", // OS disk
	}

	// Setup networking
	netdevArgs := []string{
		"user",
		"hostfwd=tcp::22-:22",
		"hostfwd=tcp::9339-:9339",
		"hostfwd=tcp::9559-:9559",
		"id=mgmt",
	}

	if *targetPort != 0 {
		// Wait for sim pipeline to start listening on the desired port before starting the VM.
		waitForPort(*targetPort, waitTimeout)
	}

	args = append(args, "-netdev", strings.Join(netdevArgs, ","))
	args = append(args, "-device", "virtio-net,netdev=mgmt")

	fmt.Println(*configFile)
	if *configFile != "" {
		dir := filepath.Dir(*configFile)
		args = append(args, "-fsdev", fmt.Sprintf("local,security_model=none,id=fsdev0,path=%s", dir),
			"-device", "virtio-9p-pci,fsdev=fsdev0,mount_tag=configfolder")
	}

	fmt.Println(args)
	cmd := exec.Command("qemu-system-x86_64", args...)
	cmd.Stderr = os.Stderr
	cmd.Stdout = os.Stdout
	cmd.Stdin = os.Stdin
	if err := cmd.Run(); err != nil {
		log.Fatal(err)
	}
}
