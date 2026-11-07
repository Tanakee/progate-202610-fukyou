package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type store struct {
	pool *pgxpool.Pool
}

func (s store) flyingBalloons(ctx context.Context) ([]Balloon, error) {
	rows, _ := s.pool.Query(ctx, `
		SELECT id, track_id, lat, lng, speed_east, speed_north
		FROM balloons WHERE status = 'flying' ORDER BY id`)
	return pgx.CollectRows(rows, pgx.RowToStructByPos[Balloon])
}

// Rails の AuthToken.digest と同じく、token の SHA-256 を16進数にして照合する
func (s store) tokenExists(ctx context.Context, token string) (bool, error) {
	digest := sha256.Sum256([]byte(token))
	var exists bool
	err := s.pool.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM auth_tokens WHERE token_digest = $1)`,
		hex.EncodeToString(digest[:])).Scan(&exists)
	return exists, err
}
