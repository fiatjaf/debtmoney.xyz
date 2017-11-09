package main

import (
	"errors"
	"time"

	"github.com/shopspring/decimal"
	b "github.com/stellar/go/build"
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

	User

	Registered bool `json:"registered" db:"registered"`

	// fields to store working values
	valueAssigned decimal.Decimal
}

func (p Party) Balance() decimal.Decimal { return p.Paid.Sub(p.Due).Abs() }

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

func (thing Thing) fillParties() (err error) {
	if thing.Parties != nil && len(thing.Parties) > 0 {
		return nil
	}

	thing.Parties = []Party{}
	err = pg.Select(&thing.Parties, `
SELECT parties.*, users.* FROM parties
INNER JOIN users ON users.id = parties.thing_id
WHERE thing_id = $1
                    `, thing.Id)
	if err != nil {
		log.Error().Str("thing", thing.Id).Err(err).
			Msg("on thing parties query")
	}
	return err
}

func (thing Thing) publish() (published bool, err error) {
	log.Info().Str("thing", thing.Id).Msg("publishing")

	err = thing.fillParties()
	if err != nil {
		return
	}

	// determining who must receive and who must issue IOUs
	// -- we trust the total owed equals the total overpaid

	var receivers []Party
	var issuers []Party
	totalLent := decimal.Decimal{}     // not the total amount paid, just the difference
	totalBorrowed := decimal.Decimal{} // not the total amount due, ...
	for _, x := range thing.Parties {
		if x.Due.GreaterThan(x.Paid) {
			issuers = append(issuers, x)
			totalLent = totalLent.Add(x.Balance())
		} else if x.Due.LessThan(x.Paid) {
			receivers = append(receivers, x)
			totalBorrowed = totalBorrowed.Add(x.Balance())
		} else {
			continue
			// this peer has paid exactly what he was due,
			// do not involve him in the transaction
		}
	}

	if !totalLent.Equals(totalBorrowed) {
		err = errors.New("unequal totals")
		return
	}

	// now whom will receive from whom?
	total := totalLent

	// -- determine the share each must receive
	// -- and make a list of all "payment pairs" we must issue
	type pair struct {
		value decimal.Decimal
		from  User
		to    User
	}
	var pairs []pair

	for _, iss := range issuers {
		totalAssigned := decimal.Decimal{}

		for i, rec := range receivers {
			var value decimal.Decimal
			if i != len(receivers)-1 {
				value = iss.Balance().
					Mul(rec.Balance()).
					DivRound(total, 2)
				totalAssigned = totalAssigned.Add(value)
			} else {
				// last one will take the remnant
				value = total.Sub(totalAssigned)
			}

			pairs = append(pairs, pair{value, iss.User, rec.User})
		}
	}

	// we must keep track of the total funding each account will have to receive
	tofund := make(map[string]int)
	for _, peer := range thing.Peers {
		tofund[peer.Id] = 0
	}

	// let's also store all the transaction operations
	var operations []b.TransactionMutator

	// keep track of all private keys that will have to be used for signing
	keys := make(map[string]string)

	// for each payment pair, we will
	for _, pair := range pairs {
		// create or expand the trustline needed
		var fund bool
		var trustness b.TransactionMutator
		var didtrust bool
		fund, trustness, didtrust, err = pair.to.trust(
			pair.from,
			thing.Asset,
			pair.value.StringFixed(2),
		)
		if err != nil {
			log.Warn().
				Str("from", pair.from.Id).
				Str("to", pair.to.Id).
				Str("value", pair.value.StringFixed(2)).
				Err(err).Msg("failed to create trustline mutator")
			return
		}

		// the transaction must always be signed by the issuing party
		keys[pair.from.Id] = pair.from.Seed
		if didtrust {
			// in the cases which no trustline was created,
			// we can't sign the transaction as the receiving party
			keys[pair.to.Id] = pair.to.Seed
		}

		operations = append(operations, trustness)
		if fund {
			tofund[pair.to.Id] += 10
		}

		// do the payment
		paymentness := b.Payment(
			b.SourceAccount{pair.from.Address},
			b.Destination{pair.to.Address},
			b.CreditAmount{thing.Asset, pair.from.Address, pair.value.StringFixed(2)},
		)
		operations = append(operations, paymentness)

		// create an offer
		var offerness b.TransactionMutator
		fund, offerness, err = pair.to.offer(
			pair.from, thing.Asset, pair.to, thing.Asset, "1", pair.value.StringFixed(2))
		if err != nil {
			log.Warn().
				Str("offerer", pair.from.Id).
				Str("asset-issuer", pair.to.Id).
				Str("value", pair.value.StringFixed(2)).
				Err(err).Msg("failed to create offer mutator")
			return
		}
		if fund {
			tofund[pair.to.Id] += 10
		}
		operations = append(operations, offerness)
	}

	// now we'll determine if the accounts need to be created
	var accountsetups []b.TransactionMutator

	for _, peer := range thing.Peers {
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

	tx.Mutate(b.MemoText{thing.Id})
	tx.Mutate(accountsetups...)
	tx.Mutate(operations...)

	seeds := make([]string, len(keys)+1)
	i := 0
	for _, key := range keys {
		seeds[i] = key
		i++
	}
	seeds[i] = s.SourceSeed

	hash, err := commitStellarTransaction(tx, seeds...)
	if err != nil {
		return false, err
	}

	published = true

	// now commit the postgres transaction
	if err == nil {
		_, err := pg.Exec(`
UPDATE thing SET txn = $1 WHERE id = $2
		    `, hash, thing.Id)

		if err != nil {
			log.Error().
				Err(err).
				Str("tx", hash).
				Msg("failed to append hash to postgres after stellar transaction ")
		}
	}

	return
}
