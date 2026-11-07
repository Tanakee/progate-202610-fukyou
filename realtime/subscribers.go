package main

import (
	"net/netip"
	"sync"
	"time"
)

// 携帯回線の NAT は数十秒から数分で対応表を消すので、端末には20秒ごとに購読を送り直してもらい、3回分届かなければ外す
const subscriberTTL = 60 * time.Second

type subscribers struct {
	mu       sync.Mutex
	lastSeen map[netip.AddrPort]time.Time
}

func newSubscribers() *subscribers {
	return &subscribers{lastSeen: map[netip.AddrPort]time.Time{}}
}

func (s *subscribers) touch(addr netip.AddrPort, now time.Time) (isNew bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	_, seen := s.lastSeen[addr]
	s.lastSeen[addr] = now
	return !seen
}

func (s *subscribers) remove(addr netip.AddrPort) {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.lastSeen, addr)
}

func (s *subscribers) active(now time.Time) []netip.AddrPort {
	s.mu.Lock()
	defer s.mu.Unlock()
	addrs := make([]netip.AddrPort, 0, len(s.lastSeen))
	for addr, seen := range s.lastSeen {
		if now.Sub(seen) > subscriberTTL {
			delete(s.lastSeen, addr)
			continue
		}
		addrs = append(addrs, addr)
	}
	return addrs
}
