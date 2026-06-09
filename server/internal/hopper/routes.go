package hopper

import (
	"fmt"
	"net"
	"sort"
)

type RouteTable struct {
	routes []parsedRoute
}

type parsedRoute struct {
	dest *net.IPNet
	via  string
}

func NewRouteTable(routes []Route) (*RouteTable, error) {
	parsed := make([]parsedRoute, 0, len(routes))
	for _, route := range routes {
		_, ipNet, err := net.ParseCIDR(route.Dest)
		if err != nil {
			return nil, fmt.Errorf("invalid route dest %q: %w", route.Dest, err)
		}
		via := route.Via
		switch via {
		case ViaIngress, ViaNext, ViaTun:
		default:
			return nil, fmt.Errorf("invalid route via %q for %s", via, route.Dest)
		}
		parsed = append(parsed, parsedRoute{dest: ipNet, via: via})
	}

	sort.Slice(parsed, func(i, j int) bool {
		iBits, _ := parsed[i].dest.Mask.Size()
		jBits, _ := parsed[j].dest.Mask.Size()
		return iBits > jBits
	})

	return &RouteTable{routes: parsed}, nil
}

func (t *RouteTable) Lookup(ip net.IP) string {
	ip = ip.To4()
	if ip == nil {
		return ViaTun
	}
	for _, route := range t.routes {
		if route.dest.Contains(ip) {
			return route.via
		}
	}
	return ViaTun
}

func IPv4Dest(packet []byte) (net.IP, error) {
	if len(packet) < 20 {
		return nil, fmt.Errorf("packet too short")
	}
	if packet[0]>>4 != 4 {
		return nil, fmt.Errorf("not ipv4")
	}
	return net.IP(packet[16:20]).To4(), nil
}
