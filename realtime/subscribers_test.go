package main

import (
	"net/netip"
	"slices"
	"testing"
	"time"
)

func TestSubscribers(t *testing.T) {
	addr := netip.MustParseAddrPort("192.0.2.1:50000")
	start := time.Date(2026, 11, 7, 12, 0, 0, 0, time.UTC)

	t.Run("初めての購読だけを新しい購読として扱う", func(t *testing.T) {
		s := newSubscribers()

		if !s.touch(addr, start) {
			t.Error("first touch should be new")
		}
		if s.touch(addr, start.Add(time.Second)) {
			t.Error("second touch should not be new")
		}
	})

	t.Run("購読を送り直している端末には送り続け、60秒を過ぎて届かない端末は外す", func(t *testing.T) {
		s := newSubscribers()
		s.touch(addr, start)

		if !slices.Contains(s.active(start.Add(subscriberTTL)), addr) {
			t.Error("subscriber should be active until the TTL")
		}
		if slices.Contains(s.active(start.Add(subscriberTTL+time.Second)), addr) {
			t.Error("subscriber should expire after the TTL")
		}
		if !s.touch(addr, start.Add(subscriberTTL+2*time.Second)) {
			t.Error("an expired subscriber should be new again")
		}
	})

	t.Run("外した端末には送らない", func(t *testing.T) {
		s := newSubscribers()
		s.touch(addr, start)

		s.remove(addr)

		if len(s.active(start)) != 0 {
			t.Error("removed subscriber should not be active")
		}
	})
}
