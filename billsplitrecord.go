package main

import (
	"github.com/shopspring/decimal"
	b "github.com/stellar/go/build"
)

type BillSplitRecord struct {
	BaseRecord

	BillSplit BillSplit
	Peers     map[string]User
}

type BillSplit struct {
	Parties map[string]struct {
		Due  string `json:"due"`
		Paid string `json:"paid"`
	}
	Object string `json:"obj"`
}

func instantiateBillSplitRecord(r BaseRecord) (d BillSplitRecord, err error) {
	d.BaseRecord = r

	err = r.Description.Unmarshal(&d.BillSplit)
	if err != nil {
		return
	}

	d.Peers = make(map[string]User)
	for id, _ := range d.BillSplit.Parties {
		var u User
		if u, err = ensureUser(id); err == nil {
			d.Peers[id] = u
		} else {
			return
		}
	}

	return
}

func (d BillSplitRecord) shouldPublish() bool {
	left := len(d.Peers)

	for _, uconfirmed := range d.Confirmed {
		if _, ok := d.BillSplit.Parties[uconfirmed]; ok {
			left--
		}
	}

	return left == 0
}

func (d BillSplitRecord) publish() error {
	log.Info().Int("record", d.Id).Msg("publishing")

	// determining who must receive and who must issue IOUs
	// -- we trust the total owed equals the total overpaid

	// also keep track of all private keys that will have to be used for signing
	var seeds []string

	receivers := make(map[string]decimal.Decimal)
	issuers := make(map[string]decimal.Decimal)
	for id, x := range d.BillSplit.Parties {
		due, _ := decimal.NewFromString(x.Due)
		paid, _ := decimal.NewFromString(x.Paid)

		if due.GreaterThan(paid) {
			issuers[id] = due.Sub(paid)
		} else if due.LessThan(paid) {
			receivers[id] = paid.Sub(due)
		} else {
			continue // this peer has paid exactly what he was due, do not involve him in the transaction
		}

		seeds = append(seeds, d.Peers[id].Seed)
	}

	// now whom will receive from whom?
	// -- make a list of all "payment pairs" we must issue
	type pair struct {
		value decimal.Decimal
		from  User
		to    User
	}
	var pairs []pair

	zero := decimal.Decimal{}
	for rid, rtotal := range receivers {
		for iid, itotal := range issuers {
			if rtotal.Equal(zero) {
				break
			}
			if itotal.Equal(zero) {
				continue
			}

			var amount decimal.Decimal
			if rtotal.GreaterThan(itotal) {
				amount = itotal
			} else {
				amount = rtotal
			}
			pairs = append(pairs, pair{itotal, d.Peers[iid], d.Peers[rid]})
			receivers[rid] = rtotal.Sub(amount)
			issuers[iid] = itotal.Sub(amount)
		}
	}

	// we must keep track of the total funding each account will have to receive
	tofund := make(map[string]int)
	for _, peer := range d.Peers {
		tofund[peer.Id] = 0
	}

	// let's also store all the transaction operations
	var operations []b.TransactionMutator

	// for each payment pair, we will
	for _, pair := range pairs {
		// create or expand the trustline needed
		fund, trustness, err := pair.to.trust(
			pair.from,
			d.Asset,
			pair.value.StringFixed(2),
		)
		if err != nil {
			log.Warn().
				Str("from", pair.from.Id).
				Str("to", pair.to.Id).
				Str("value", pair.value.StringFixed(2)).
				Err(err).Msg("failed to create trustline mutator")
			return err
		}
		operations = append(operations, trustness)
		if fund {
			tofund[pair.to.Id] += 10
		}

		// do the payment
		paymentness := b.Payment(
			b.SourceAccount{pair.from.Address},
			b.Destination{pair.to.Address},
			b.CreditAmount{d.Asset, pair.from.Address, pair.value.StringFixed(2)},
		)
		operations = append(operations, paymentness)

		// create an offer
		fund, offerness, err := pair.to.offer(
			pair.from, d.Asset, pair.to, d.Asset, "1", pair.value.StringFixed(2))
		if err != nil {
			log.Warn().
				Str("offerer", pair.from.Id).
				Str("asset-issuer", pair.to.Id).
				Str("value", pair.value.StringFixed(2)).
				Err(err).Msg("failed to create offer mutator")
			return err
		}
		if fund {
			tofund[pair.to.Id] += 10
		}
		operations = append(operations, offerness)
	}

	// now we'll determine if the accounts need to be created
	var accountsetups []b.TransactionMutator

	for _, peer := range d.Peers {
		neededfunds := tofund[peer.Id]

		if peer.ha.ID == "" {
			// doesn't exist on stellar, will create
			accountness := peer.fundInitial(neededfunds + 20)
			accountsetups = append(accountsetups, accountness)
		} else if neededfunds > 0 {
			accountness := peer.fund(neededfunds)
			accountsetups = append(accountsetups, accountness)
		}
	}

	log.Info().Msg("publishing a single transaction")
	tx := createStellarTransaction()

	tx.Mutate(accountsetups...)
	tx.Mutate(operations...)

	seeds = append(seeds, s.SourceSeed)
	hash, err := commitStellarTransaction(tx, seeds...)
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
