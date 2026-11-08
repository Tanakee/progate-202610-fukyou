package main

import (
	"encoding/binary"
	"math"
)

const (
	typeSubscribe byte = 0x01
	typeSnapshot  byte = 0x02
	typeError     byte = 0x7f

	errUnauthorized byte = 0x01

	// IPv6 で分割されずに届く最小の大きさ（1,280バイト）から、IP と UDP のヘッダーを引いた値
	maxPacketSize     = 1200
	headerSize        = 1 + 8 + 4 + 2 + 2 + 2
	balloonSize       = 4 * 6
	balloonsPerPacket = (maxPacketSize - headerSize) / balloonSize
)

type Balloon struct {
	ID, TrackID                     int64
	Lat, Lng, SpeedEast, SpeedNorth float64
}

// snapshot を、1つずつ届かなくても読めるよう、どのパケットにも見出しを付けて分ける。
// 風船がなくても、空になったことを伝えるために1つは送る
func encodeSnapshot(seq uint64, speedScale float32, balloons []Balloon) [][]byte {
	total := max(1, (len(balloons)+balloonsPerPacket-1)/balloonsPerPacket)
	packets := make([][]byte, 0, total)
	for part := range total {
		chunk := balloons[min(part*balloonsPerPacket, len(balloons)):min((part+1)*balloonsPerPacket, len(balloons))]

		p := make([]byte, 0, headerSize+len(chunk)*balloonSize)
		p = append(p, typeSnapshot)
		p = binary.BigEndian.AppendUint64(p, seq)
		p = binary.BigEndian.AppendUint32(p, math.Float32bits(speedScale))
		p = binary.BigEndian.AppendUint16(p, uint16(part))
		p = binary.BigEndian.AppendUint16(p, uint16(total))
		p = binary.BigEndian.AppendUint16(p, uint16(len(chunk)))
		for _, b := range chunk {
			// ID を8バイトにしないのは、42億を超える風船や曲は想定せず、1パケットに入る数を増やしたいから
			p = binary.BigEndian.AppendUint32(p, uint32(b.ID))
			p = binary.BigEndian.AppendUint32(p, uint32(b.TrackID))
			// 緯度経度を float64 にしないのは、float32 でも誤差が1m未満で、地図の表示には足りるから
			for _, v := range []float64{b.Lat, b.Lng, b.SpeedEast, b.SpeedNorth} {
				p = binary.BigEndian.AppendUint32(p, math.Float32bits(float32(v)))
			}
		}
		packets = append(packets, p)
	}
	return packets
}

func errorPacket(code byte) []byte {
	return []byte{typeError, code}
}
