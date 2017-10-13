package main

import (
	"errors"
	"time"

	"github.com/jmoiron/sqlx/types"
)

type BaseRecord struct {
	Id           int            `json:"id"           db:"id"`
	CreatedAt    time.Time      `json:"created_at"   db:"created_at"`
	RecordDate   time.Time      `json:"record_date"  db:"record_date"`
	Kind         string         `json:"kind"         db:"kind"`
	Asset        string         `json:"asset"        db:"asset"`
	Description  types.JSONText `json:"description"  db:"description"`
	Confirmed    StringSlice    `json:"confirmed"    db:"confirmed"`
	Transactions StringSlice    `json:"transactions" db:"transactions"`
}

func confirmRecord(recordId int, userId string) error {
	log.Info().
		Int("record", recordId).
		Str("user", userId).
		Msg("updating record with confirmation")

	var r BaseRecord
	err := pg.Get(&r, `
UPDATE records
SET confirmed = array_append(confirmed, $1)
WHERE id = $2
RETURNING *
    `, userId, recordId)
	if err != nil {
		log.Error().Err(err).Msg("error appending confirmation")
		return errors.New("couldn't confirm.")
	}

	// now we examine to see if we must publish this.
	switch r.Kind {
	case "debt":
		d, err := instantiateDebtRecord(r)
		if err != nil {
			return err
		}
		return d.confirmed()
	case "payment":
	case "bill-split":
	}

	return errors.New("should never happen")
}
