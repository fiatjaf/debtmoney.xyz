package main

import (
	b "github.com/stellar/go/build"
)

type PaymentRecord struct {
	BaseRecord

	Payment Payment
	Payer   User
	Payee   User
}

type Payment struct {
	Payee  string `json:"debtor"`
	Payer  string `json:"creditor"`
	Amount string `json:"amt"`
	Object string `json:"obj"`
}

func instantiatePaymentRecord(r BaseRecord) (d PaymentRecord, err error) {
	d.BaseRecord = r

	err = r.Description.Unmarshal(&d.Payment)
	if err != nil {
		return
	}

	var u User
	if u, err = ensureUser(d.Payment.Payee); err == nil {
		d.Payee = u
	} else {
		return
	}
	if u, err = ensureUser(d.Payment.Payer); err == nil {
		d.Payer = u
	} else {
		return
	}

	return
}

func (d PaymentRecord) shouldPublish() bool {
	var payeeConfirmed bool
	var payerConfirmed bool
	for _, uconfirmed := range d.Confirmed {
		if uconfirmed == d.Payment.Payee {
			payeeConfirmed = true
		}
		if uconfirmed == d.Payment.Payer {
			payerConfirmed = true
		}
	}
	if payeeConfirmed && payerConfirmed {
		return true
	}

	return false
}

func (d PaymentRecord) publish() error {
	log.Info().Int("record", d.Id).Msg("publishing")

	fundtotal := 0 // extra balance reserve needed to the receiver of the IOU

	fund, trustness, err := d.Payer.trust(d.Payee, d.Asset, d.Payment.Amount)
	if err != nil {
		log.Warn().Err(err).Msg("failed to create trustline mutator")
		return err
	}
	if fund {
		fundtotal += 10
	}

	paymentness := b.Payment(
		b.SourceAccount{d.Payee.Address},
		b.Destination{d.Payer.Address},
		b.CreditAmount{d.Asset, d.Payee.Address, d.Payment.Amount},
	)

	fund, offerness, err := d.Payer.offer(
		d.Payee, d.Asset, d.Payer, d.Asset, "1", d.Payment.Amount)
	if err != nil {
		log.Warn().Err(err).Msg("failed to create offer mutator")
		return err
	}
	if fund {
		fundtotal += 10
	}

	log.Info().Msg("publishing a single transaction")
	tx := createStellarTransaction()

	var issuerness b.TransactionMutator
	var receiverness b.TransactionMutator

	if d.Payee.ha.ID == "" {
		// account doesn't exist on stellar
		issuerness = d.Payee.fundInitial(20)
	} else {
		issuerness = b.Defaults{}
	}

	if d.Payer.ha.ID == "" {
		// account doesn't exist on stellar
		receiverness = d.Payer.fundInitial(fundtotal + 20)
	} else {
		receiverness = d.Payer.fund(fundtotal)
	}

	tx.Mutate(
		b.MemoID{uint64(d.Id)},
		issuerness,
		receiverness,
		trustness,
		paymentness,
		offerness,
	)

	hash, err := commitStellarTransaction(tx, s.SourceSeed, d.Payer.Seed, d.Payee.Seed)
	if err != nil {
		return err
	}

	// now commit the postgres transaction
	if err == nil {
		_, err := pg.Exec(`
UPDATE records
   SET transactions = array_append(transactions, $2)
 WHERE id = $1
    `, d.Id, hash)

		if err != nil {
			log.Error().
				Err(err).
				Str("tx", hash).
				Msg("failed to append hash to postgres after stellar transaction ")
		}
	}

	return err
}
