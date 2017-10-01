package main

import (
	"encoding/json"
	"errors"

	"github.com/jmoiron/sqlx/types"
	b "github.com/stellar/go/build"
)

type DebtRecord struct {
	BaseRecord

	From User
	To   User
}

type Debt struct {
	From   string `json:"from"` // the one who owes
	To     string `json:"to"`   // the one who is owed
	Amount string `json:"amt"`
}

func (me User) simpleDebt(from, to, assetCode, amount string) (*DebtRecord, error) {
	var r DebtRecord

	desc, _ := json.Marshal(Debt{
		From:   from,
		To:     to,
		Amount: amount,
	})

	err := pg.Get(&r, `
INSERT INTO records (kind, description, asset, confirmed)
VALUES ('debt', $1, $2, $3)
RETURNING *
    `, types.JSONText(desc), assetCode, StringSlice{me.Id})

	return &r, err
}

func (r *DebtRecord) Confirm(userId string) error {
	log.Info().
		Int("record", r.Id).
		Str("user", userId).
		Msg("updating record with confirmation")
	pg.Get(r, `
UPDATE records
SET confirmed = array_append(confirmed, $1)
WHERE id = $2
RETURNING *
    `, userId, r.Id)

	log.Info().Msg("unmarshaling debt desc")
	var desc Debt
	err := r.Description.Unmarshal(&desc)
	if err != nil {
		return err
	}
	var fromConfirmed bool
	var toConfirmed bool
	for _, uconfirmed := range r.Confirmed {
		if uconfirmed == desc.From {
			fromConfirmed = true
		}
		if uconfirmed == desc.To {
			toConfirmed = true
		}
	}
	if fromConfirmed && toConfirmed {
		log.Info().Msg("all confirmed, let's publish")
		return r.Publish()
	}

	return errors.New("couldn't confirm.")
}

func (r DebtRecord) Publish() error {
	log.Info().Int("record", r.Id).Msg("publishing")
	log.Info().Msg("fetching debt desc")
	var desc Debt
	err := r.Description.Unmarshal(&desc)
	if err != nil {
		return err
	}

	log.Info().Msg("adjusting trustline")
	err = r.To.trust(r.From, r.Asset, desc.Amount)
	if err != nil {
		return err
	}

	log.Info().Msg("publishing a single transaction")
	tx := b.Transaction(
		n,
		b.SourceAccount{r.From.Address},
		b.AutoSequence{h},
		b.Payment(
			b.Destination{r.To.Address},
			b.CreditAmount{r.Asset, r.From.Address, desc.Amount},
		),
	)
	if tx.Err != nil {
		return tx.Err
	}

	txe := tx.Sign(r.From.Seed)
	blob, err := txe.Base64()
	if err != nil {
		return err
	}

	_, err = h.SubmitTransaction(blob)
	if err != nil {
		return err
	}
	return nil
}
