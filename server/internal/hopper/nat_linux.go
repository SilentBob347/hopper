//go:build linux

package hopper

import (
	"fmt"
	"os/exec"
	"strings"

	"github.com/aengix/hopper/server/internal/log"
)

func setupNAT(overlay, tunName string) error {
	if overlay == "" {
		overlay = DefaultOverlay
	}
	if tunName == "" {
		tunName = DefaultTUN
	}

	_ = exec.Command("sysctl", "-w", "net.ipv4.ip_forward=1").Run()
	_ = exec.Command("sysctl", "-w", "net.ipv4.conf.all.rp_filter=0").Run()
	_ = exec.Command("sysctl", "-w", "net.ipv4.conf.default.rp_filter=0").Run()

	if _, err := exec.LookPath("iptables"); err != nil {
		log.Warnf("iptables not found — overlay NAT disabled")
		return nil
	}

	iface, err := defaultRouteIface()
	if err != nil {
		log.Warnf("default route iface: %v — overlay NAT skipped", err)
		return nil
	}

	rules := [][]string{
		{"-t", "nat", "-C", "POSTROUTING", "-s", overlay, "-o", iface, "-j", "MASQUERADE"},
		{"-C", "FORWARD", "-i", tunName, "-j", "ACCEPT"},
		{"-C", "FORWARD", "-o", tunName, "-j", "ACCEPT"},
		{"-C", "FORWARD", "-m", "state", "--state", "RELATED,ESTABLISHED", "-j", "ACCEPT"},
	}
	addRules := [][]string{
		{"-t", "nat", "-A", "POSTROUTING", "-s", overlay, "-o", iface, "-j", "MASQUERADE"},
		{"-A", "FORWARD", "-i", tunName, "-j", "ACCEPT"},
		{"-A", "FORWARD", "-o", tunName, "-j", "ACCEPT"},
		{"-A", "FORWARD", "-m", "state", "--state", "RELATED,ESTABLISHED", "-j", "ACCEPT"},
	}

	for i, check := range rules {
		if out, err := exec.Command("iptables", check...).CombinedOutput(); err != nil {
			if addOut, addErr := exec.Command("iptables", addRules[i]...).CombinedOutput(); addErr != nil {
				return fmt.Errorf("iptables %v: %s (%w)", addRules[i], strings.TrimSpace(string(addOut)), addErr)
			}
			log.Infof("iptables added: %v", addRules[i])
		} else {
			_ = out
		}
	}

	log.Infof("NAT enabled overlay=%s out=%s tun=%s", overlay, iface, tunName)
	return nil
}

func defaultRouteIface() (string, error) {
	out, err := exec.Command("ip", "route", "show", "default").Output()
	if err != nil {
		return "", err
	}
	fields := strings.Fields(string(out))
	for i, f := range fields {
		if f == "dev" && i+1 < len(fields) {
			return fields[i+1], nil
		}
	}
	return "", fmt.Errorf("no default route")
}
