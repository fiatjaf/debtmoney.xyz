package main

import (
	b "github.com/stellar/go/build"
)

type DebtRecord struct {
	BaseRecord

	Debt Debt
	From User
	To   User
}

type Debt struct {
	From   string `json:"from"` // the one who owes
	To     string `json:"to"`   // the one who is owed
	Amount string `json:"amt"`
}

func instantiateDebtRecord(r BaseRecord) (d DebtRecord, err error) {
	d.BaseRecord = r

	err = r.Description.Unmarshal(&d.Debt)
	if err != nil {
		return
	}

	var u User
	if u, err = ensureUser(d.Debt.From); err == nil {
		d.From = u
	} else {
		return
	}
	if u, err = ensureUser(d.Debt.To); err == nil {
		d.To = u
	} else {
		return
	}

	return
}

func (d DebtRecord) confirmed() error {
	var fromConfirmed bool
	var toConfirmed bool
	for _, uconfirmed := range d.Confirmed {
		if uconfirmed == d.Debt.From {
			fromConfirmed = true
		}
		if uconfirmed == d.Debt.To {
			toConfirmed = true
		}
	}
	if fromConfirmed && toConfirmed {
		log.Info().Msg("all confirmed, let's publish")
		return d.publish()
	}

	return nil
}

func (d DebtRecord) publish() error {
	log.Info().Int("record", d.Id).Msg("publishing")

	err = d.To.trust(d.From, d.Asset, d.Debt.Amount)
	if err != nil {
		log.Error().Err(err).Msg("failed to adjust trustline")
		return err
	}

	log.Info().Msg("publishing a single transaction")
	tx := b.Transaction(
		n,
		b.SourceAccount{d.From.Address},
		b.AutoSequence{h},
		b.Payment(
			b.Destination{d.To.Address},
			b.CreditAmount{d.Asset, d.From.Address, d.Debt.Amount},
		),
	)
	if tx.Err != nil {
		log.Error().Err(err).Msg("failed to build transaction")
		return tx.Err
	}

	txe := tx.Sign(d.From.Seed)
	blob, err := txe.Base64()
	if err != nil {
		log.Error().Err(err).Msg("failed to sign transaction")
		return err
	}

	success, err := h.SubmitTransaction(blob)
	if err != nil {
		log.Error().Err(err).Msg("failed to build transaction")
		return err
	}

	// published successfully, append to record
	_, err = pg.Exec(`
UPDATE records
   SET transactions = array_append(transactions, $2)
 WHERE id = $1
    `, d.Id, success.Hash)
	if err != nil {
		log.Error().
			Err(err).
			Str("hash", success.Hash).
			Msg("failed to append transaction to record")
	}

	return nil
}
