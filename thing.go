package main

import (
	"errors"
	"time"

	"github.com/shopspring/decimal"
)

type Thing struct {
	Id          string    `json:"id"           db:"id"`
	CreatedAt   time.Time `json:"created_at"   db:"created_at"`
	ThingDate   time.Time `json:"thing_date"   db:"thing_date"`
	Name        string    `json:"name"         db:"name"`
	Asset       string    `json:"asset"        db:"asset"`
	Transaction string    `json:"txn"          db:"txn"`

	Publishable bool `json:"-" db:"publishable"`

	Parties []Party `json:"parties"`

	Peers map[string]User `json:"-"`
}

type Party struct {
	UserId    string          `json:"user_id"    db:"user_id"`
	ThingId   string          `json:"thing_id"   db:"thing_id"`
	Paid      decimal.Decimal `json:"paid"       db:"paid"`
	Due       decimal.Decimal `json:"due"        db:"due"`
	Confirmed bool            `json:"confirmed"  db:"confirmed"`

	Registered bool `json:"registered" db:"registered"`
}

func confirmThing(id string, userId string) (thing Thing, published bool, err error) {
	log.Info().
		Str("thing", id).
		Str("user", userId).
		Msg("updating record with confirmation")

	err = pg.Get(&thing, `
WITH upd AS (
  UPDATE parties
  SET confirmed = true
  WHERE thing_id = $1 AND user_id = $2
  RETURNING thing_id
)
SELECT *, publishable FROM things
WHERE id = upd
    `, id, userId)
	if err != nil {
		log.Error().Err(err).Msg("error appending confirmation")
		return thing, false, errors.New("couldn't confirm.")
	}

	if thing.Publishable {
		published, err = thing.publish()
	}

	return
}

func instantiateThing(r Thing) (err error) {
	// 	d.Peers = make(map[string]User)
	// 	var u User
	//
	// 	for _, peeramount := range d.Dues {
	// 		if u, err = ensureUser(id); err != nil {
	// 			return
	// 		}
	// 		d.Peers[id] = u
	// 	}
	//
	// 	for _, peeramount := range d.Payments {
	// 		if _, alreadythere := d.Peers[id]; alreadythere {
	// 			continue
	// 		}
	//
	// 		if u, err = ensureUser(id); err != nil {
	// 			return
	// 		}
	// 		d.Peers[id] = u
	// 	}
	//
	return
}

func (thing Thing) publish() (published bool, err error) {
	/*
			log.Info().Int("thing", thing.Id).Msg("publishing")

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

			tx.Mutate(b.MemoID{uint64(d.Id)})
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
	*/
	return
}
