package main

import (
	b "github.com/stellar/go/build"
)

type DebtRecord struct {
	BaseRecord

	Debt     Debt
	Debtor   User
	Creditor User
}

type Debt struct {
	Debtor   string `json:"debtor"`
	Creditor string `json:"creditor"`
	Amount   string `json:"amt"`
}

func instantiateDebtRecord(r BaseRecord) (d DebtRecord, err error) {
	d.BaseRecord = r

	err = r.Description.Unmarshal(&d.Debt)
	if err != nil {
		return
	}

	var u User
	if u, err = ensureUser(d.Debt.Debtor); err == nil {
		d.Debtor = u
	} else {
		return
	}
	if u, err = ensureUser(d.Debt.Creditor); err == nil {
		d.Creditor = u
	} else {
		return
	}

	return
}

func (d DebtRecord) shouldPublish() bool {
	var debtorConfirmed bool
	var creditorConfirmed bool
	for _, uconfirmed := range d.Confirmed {
		if uconfirmed == d.Debt.Debtor {
			debtorConfirmed = true
		}
		if uconfirmed == d.Debt.Creditor {
			creditorConfirmed = true
		}
	}
	if debtorConfirmed && creditorConfirmed {
		return true
	}

	return false
}

func (d DebtRecord) publish() error {
	log.Info().Int("record", d.Id).Msg("publishing")

	fundtotal := 0 // extra balance reserve needed to the receiver of the IOU

	fund, trustness, err := d.Creditor.trust(d.Debtor, d.Asset, d.Debt.Amount)
	if err != nil {
		log.Warn().Err(err).Msg("failed to create trustline mutator")
		return err
	}
	if fund {
		fundtotal += 10
	}

	paymentness := b.Payment(
		b.SourceAccount{d.Debtor.Address},
		b.Destination{d.Creditor.Address},
		b.CreditAmount{d.Asset, d.Debtor.Address, d.Debt.Amount},
	)

	fund, offerness, err := d.Creditor.offer(
		d.Debtor, d.Asset, d.Creditor, d.Asset, "1", d.Debt.Amount)
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

	if d.Debtor.ha.ID == "" {
		// account doesn't exist on stellar
		issuerness = d.Debtor.fundInitial(20)
	} else {
		issuerness = b.Defaults{}
	}

	if d.Creditor.ha.ID == "" {
		// account doesn't exist on stellar
		receiverness = d.Creditor.fundInitial(fundtotal + 20)
	} else {
		receiverness = d.Creditor.fund(fundtotal)
	}

	tx.Mutate(
		b.MemoID{uint64(d.Id)},
		issuerness,
		receiverness,
		trustness,
		paymentness,
		offerness,
	)

	hash, err := commitStellarTransaction(tx, s.SourceSeed, d.Creditor.Seed, d.Debtor.Seed)
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
