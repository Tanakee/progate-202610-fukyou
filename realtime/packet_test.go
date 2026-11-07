package main

import (
	"encoding/binary"
	"math"
	"testing"
)

func TestEncodeSnapshot(t *testing.T) {
	t.Run("見出しに seq・速さの倍率・何番目か・全部でいくつか・風船の数を入れ、風船は24バイトずつ並べる", func(t *testing.T) {
		packets := encodeSnapshot(1730000000000, 300, []Balloon{{ID: 7, TrackID: 3, Lat: 33.5, Lng: 130.25, SpeedEast: -1.5, SpeedNorth: 2}})

		if len(packets) != 1 {
			t.Fatalf("packets = %d, want 1", len(packets))
		}
		p := packets[0]
		if len(p) != headerSize+balloonSize {
			t.Fatalf("len = %d, want %d", len(p), headerSize+balloonSize)
		}
		got := []any{
			p[0],
			binary.BigEndian.Uint64(p[1:9]),
			math.Float32frombits(binary.BigEndian.Uint32(p[9:13])),
			binary.BigEndian.Uint16(p[13:15]),
			binary.BigEndian.Uint16(p[15:17]),
			binary.BigEndian.Uint16(p[17:19]),
			binary.BigEndian.Uint32(p[19:23]),
			binary.BigEndian.Uint32(p[23:27]),
			math.Float32frombits(binary.BigEndian.Uint32(p[27:31])),
			math.Float32frombits(binary.BigEndian.Uint32(p[31:35])),
			math.Float32frombits(binary.BigEndian.Uint32(p[35:39])),
			math.Float32frombits(binary.BigEndian.Uint32(p[39:43])),
		}
		want := []any{typeSnapshot, uint64(1730000000000), float32(300), uint16(0), uint16(1), uint16(1),
			uint32(7), uint32(3), float32(33.5), float32(130.25), float32(-1.5), float32(2)}
		for i := range want {
			if got[i] != want[i] {
				t.Errorf("field %d = %v, want %v", i, got[i], want[i])
			}
		}
	})

	t.Run("1パケットが1,200バイトを超えないよう分け、全部の風船をどれかのパケットに入れる", func(t *testing.T) {
		balloons := make([]Balloon, balloonsPerPacket*2+1)
		for i := range balloons {
			balloons[i].ID = int64(i + 1)
		}

		packets := encodeSnapshot(1, 1, balloons)

		if len(packets) != 3 {
			t.Fatalf("packets = %d, want 3", len(packets))
		}
		var ids []uint32
		for i, p := range packets {
			if len(p) > maxPacketSize {
				t.Errorf("packet %d is %d bytes", i, len(p))
			}
			if part, total := binary.BigEndian.Uint16(p[13:15]), binary.BigEndian.Uint16(p[15:17]); part != uint16(i) || total != 3 {
				t.Errorf("packet %d says part %d of %d", i, part, total)
			}
			for j := range int(binary.BigEndian.Uint16(p[17:19])) {
				ids = append(ids, binary.BigEndian.Uint32(p[headerSize+j*balloonSize:]))
			}
		}
		if len(ids) != len(balloons) || ids[0] != 1 || ids[len(ids)-1] != uint32(len(balloons)) {
			t.Errorf("ids = %d items from %d to %d, want 1..%d", len(ids), ids[0], ids[len(ids)-1], len(balloons))
		}
	})

	t.Run("飛んでいる風船がなくても、空になったことを伝える1パケットを作る", func(t *testing.T) {
		packets := encodeSnapshot(1, 1, nil)

		if len(packets) != 1 || len(packets[0]) != headerSize || binary.BigEndian.Uint16(packets[0][17:19]) != 0 {
			t.Errorf("packets = %v", packets)
		}
	})
}
