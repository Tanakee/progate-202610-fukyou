package main

import (
	"context"
	"log/slog"
	"net"
	"net/netip"
	"os"
	"strconv"
	"sync/atomic"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

const interval = 5 * time.Second

type server struct {
	conn        *net.UDPConn
	store       store
	subscribers *subscribers
	speedScale  float32
	latest      atomic.Pointer[[][]byte]
}

func main() {
	ctx := context.Background()

	// 接続先を DB_HOST などから組み立てないのは、pgx が libpq と同じ PGHOST・PGUSER・PGPASSWORD・PGDATABASE を読むから
	pool, err := pgxpool.New(ctx, "")
	if err != nil {
		fail("connect to database", err)
	}
	defer pool.Close()

	addr, err := net.ResolveUDPAddr("udp", envOr("ADDR", ":4000"))
	if err != nil {
		fail("resolve address", err)
	}
	conn, err := net.ListenUDP("udp", addr)
	if err != nil {
		fail("listen", err)
	}
	defer conn.Close()

	speedScale, err := strconv.ParseFloat(envOr("SPEED_SCALE", "1"), 32)
	if err != nil {
		fail("parse SPEED_SCALE", err)
	}

	s := &server{conn: conn, store: store{pool}, subscribers: newSubscribers(), speedScale: float32(speedScale)}
	slog.Info("listening", "addr", conn.LocalAddr().String())
	go s.broadcastEvery(ctx, interval)
	s.serve(ctx)
}

func (s *server) serve(ctx context.Context) {
	buf := make([]byte, maxPacketSize)
	for {
		n, addr, err := s.conn.ReadFromUDPAddrPort(buf)
		if err != nil {
			slog.Error("read", "error", err)
			continue
		}
		if n < 1 || buf[0] != typeSubscribe {
			continue
		}
		s.subscribe(ctx, addr, string(buf[1:n]))
	}
}

func (s *server) subscribe(ctx context.Context, addr netip.AddrPort, token string) {
	ok, err := s.store.tokenExists(ctx, token)
	if err != nil {
		slog.Error("verify token", "error", err)
		return
	}
	if !ok {
		// ログアウトした端末にも送り続けないよう、購読中でも外す
		s.subscribers.remove(addr)
		s.send(addr, errorPacket(errUnauthorized))
		return
	}
	// 接続した直後に地図を出せるよう、次の配信を待たずに最新の snapshot を送る
	if s.subscribers.touch(addr, time.Now()) {
		if packets := s.latest.Load(); packets != nil {
			s.send(addr, *packets...)
		}
	}
}

func (s *server) broadcastEvery(ctx context.Context, every time.Duration) {
	for now := range time.Tick(every) {
		balloons, err := s.store.flyingBalloons(ctx)
		if err != nil {
			slog.Error("load balloons", "error", err)
			continue
		}
		packets := encodeSnapshot(uint64(now.UnixMilli()), s.speedScale, balloons)
		s.latest.Store(&packets)
		for _, addr := range s.subscribers.active(now) {
			s.send(addr, packets...)
		}
	}
}

func (s *server) send(addr netip.AddrPort, packets ...[]byte) {
	for _, p := range packets {
		if _, err := s.conn.WriteToUDPAddrPort(p, addr); err != nil {
			slog.Error("write", "addr", addr.String(), "error", err)
		}
	}
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func fail(what string, err error) {
	slog.Error(what, "error", err)
	os.Exit(1)
}
