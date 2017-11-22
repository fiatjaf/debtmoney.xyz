package main

import (
	"errors"
	"fmt"
	"strings"
	"sync"

	"github.com/jmoiron/sqlx"
	"github.com/shopspring/decimal"
	b "github.com/stellar/go/build"
)

type Thing struct {
	Id          string          `json:"id"            db:"id"`
	CreatedAt   string          `json:"created_at"    db:"created_at"`
	ActualDate  string          `json:"actual_date"   db:"actual_date"`
	CreatedBy   string          `json:"created_by"    db:"created_by"`
	Name        string          `json:"name"          db:"name"`
	Asset       string          `json:"asset"         db:"asset"`
	TotalDue    decimal.Decimal `json:"total_due"     db:"total_due"`
	TotalDueSet bool            `json:"total_due_set" db:"total_due_set"`
	Transaction string          `json:"txn"           db:"txn"`
	Publishable bool            `json:"publishable"   db:"publishable"`

	Parties []Party `json:"parties"`

	Peers map[string]User `json:"-"`
}

func (thing Thing) columns() string {
	return `
things.id,
created_at,
actual_date,
created_by,
coalesce(name, '') AS name,
coalesce(total_due, '0') AS total_due,
total_due IS NOT NULL AS total_due_set,
asset,
coalesce(txn, '') AS txn,
things.publishable
    `
}

func (thing *Thing) fillParties() (err error) {
	if thing.Parties != nil && len(thing.Parties) > 0 {
		return nil
	}

	thing.Parties = []Party{}
	err = pg.Select(
		&thing.Parties, `
SELECT `+(Party{}).columns()+`, `+(User{}).columns()+`
FROM parties
LEFT JOIN users ON users.id = parties.user_id
WHERE thing_id = $1;
        `, thing.Id)
	if err != nil {
		log.Error().Str("thing", thing.Id).Err(err).
			Msg("on thing parties query")
		return
	}

	// load accounts info from stellar
	// ignore errors -- because the account may not be created on stellar yet
	var wg sync.WaitGroup
	for i, x := range thing.Parties {
		wg.Add(1)
		go func(index int, addr string) {
			defer wg.Done()
			ha, _ := h.LoadAccount(addr)
			thing.Parties[index].User.ha = ha
		}(i, x.User.Address)
	}
	wg.Wait()

	return
}

type Party struct {
	ThingId     string          `json:"thing_id"     db:"thing_id"`
	UserId      string          `json:"user_id"      db:"user_id"`
	AccountName string          `json:"account_name" db:"account_name"`
	Paid        decimal.Decimal `json:"paid"         db:"paid"`
	Due         decimal.Decimal `json:"due"          db:"due"`
	DueSet      bool            `json:"due_set"      db:"due_set"`
	Note        string          `json:"note"         db:"note"`
	AddedBy     string          `json:"added_by"     db:"added_by"`
	Confirmed   bool            `json:"confirmed"    db:"confirmed"`

	workingDue decimal.Decimal `json:"-"`

	User `json:"-"`
}

func (p Party) columns() string {
	return `
thing_id, account_name, added_by, confirmed,
coalesce(due, '0') AS due,
due IS NOT NULL AS due_set,
coalesce(paid, '0') AS paid,
coalesce(user_id, '') AS user_id,
coalesce(note, '') AS note
    `
}

func insertThing(
	txn *sqlx.Tx,
	id, date, user_id, name, asset, total_due string,
	parties []interface{},
) (Thing, error) {
	log.Info().Str("thing", id).Msg("inserting thing in transaction")
	var thing Thing
	var err error

	err = txn.Get(&thing, `
INSERT INTO things (id, actual_date, name, asset, total_due, created_by)
VALUES ($1, $2, $3, $4, nullable($5), $6)
RETURNING `+thing.columns(),
		id, date, name, asset, total_due, user_id)
	if err != nil {
		log.Warn().Err(err).Msg("when inserting a new thing")
		return thing, err
	}

	partiesSQL := make([]string, len(parties))
	partiesValues := make([]interface{}, len(parties)*6)
	for i, iparty := range parties {
		party := iparty.(map[string]interface{})
		partiesSQL[i] = fmt.Sprintf(`
(
  (SELECT id FROM users WHERE id = $%d),
  $%d,
  $%d,
  nullable($%d),
  nullable($%d),
  $%d
)
        `, i*6+1, i*6+2, i*6+3, i*6+4, i*6+5, i*6+6)
		partiesValues[(i*6)+0] = party["account"]
		partiesValues[(i*6)+1] = party["account"]
		partiesValues[(i*6)+2] = id
		partiesValues[(i*6)+3] = party["due"]
		partiesValues[(i*6)+4] = party["paid"]
		partiesValues[(i*6)+5] = user_id
	}

	err = txn.Select(&thing.Parties, `
INSERT INTO parties (user_id, account_name, thing_id, due, paid, added_by)
VALUES `+strings.Join(partiesSQL, ",")+`
RETURNING `+(Party{}).columns(),
		partiesValues...)
	if err != nil {
		log.Warn().Err(err).Msg("when inserting all parties for a thing")
		return thing, err
	}
	return thing, err
}

func deleteThing(txn *sqlx.Tx, id string) error {
	log.Info().Str("thing", id).Msg("deleting thing in transaction")

	var hash string
	err := txn.Get(&hash, `
WITH dp AS ( DELETE FROM parties WHERE thing_id = $1 )
   , dt AS ( DELETE FROM things WHERE id = $1 )
SELECT txn FROM things WHERE id = $1
    `, id)
	if err != nil {
		return err
	}
	if hash != "" {
		return errors.New("transaction already published, can't delete")
	}

	return nil
}

func confirmThing(id, userId string, confirm bool) (thing Thing, published bool, err error) {
	log.Info().
		Str("thing", id).
		Str("user", userId).
		Bool("confirm", confirm).
		Msg("updating record with confirmation")

	err = pg.Get(&thing, `
WITH upd AS (
  UPDATE parties
  SET confirmed = $3
  WHERE thing_id = $1 AND user_id = $2
  RETURNING thing_id
)
SELECT `+thing.columns()+`, things.publishable FROM things
WHERE id = (SELECT thing_id FROM upd)
    `, id, userId, confirm)
	if err != nil {
		log.Error().Err(err).Msg("error appending confirmation")
		return thing, false, errors.New("couldn't confirm.")
	}

	if thing.Publishable {
		published, err = thing.publish()
	}

	return
}

func (thing Thing) publish() (published bool, err error) {
	log.Info().Str("thing", thing.Id).Msg("publishing")

	if thing.Transaction != "" {
		log.Info().Str("txn", thing.Transaction).Msg("already published")
		published = true
		return
	}

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

	var splittedDue decimal.Decimal
	remainingDue := decimal.Decimal{}
	if thing.TotalDueSet {
		dueUnsetCount := int64(0)
		totalSet := decimal.Decimal{}
		for _, x := range thing.Parties {
			if x.DueSet {
				totalSet = totalSet.Add(x.Due)
			} else {
				dueUnsetCount += 1
			}
		}
		remainingDue = thing.TotalDue.Sub(totalSet)
		splittedDue = remainingDue.DivRound(decimal.New(dueUnsetCount, 0), 2)
	}

	for i, x := range thing.Parties {
		x.workingDue = x.Due
		if !x.DueSet {
			if i == len(thing.Parties)-1 {
				x.workingDue = remainingDue
			} else {
				x.workingDue = splittedDue
				remainingDue = remainingDue.Sub(splittedDue)
			}
		}

		if x.workingDue.GreaterThan(x.Paid) {
			issuers = append(issuers, x)
			totalBorrowed = totalBorrowed.Add(x.workingDue.Sub(x.Paid))
		} else if x.workingDue.LessThan(x.Paid) {
			receivers = append(receivers, x)
			totalLent = totalLent.Add(x.Paid.Sub(x.workingDue))
		} else {
			continue
			// this peer has paid exactly what he was due,
			// do not involve him in the transaction
		}
	}

	if !totalLent.Equals(totalBorrowed) {
		err = errors.New("unequal totals")
		log.Warn().
			Err(err).
			Str("lent", totalLent.String()).
			Str("borrowed", totalBorrowed.String()).
			Msg("when publishing transaction")
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
				value = iss.workingDue.Sub(iss.Paid).
					Mul(rec.Paid.Sub(rec.workingDue)).
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
	for _, party := range thing.Parties {
		tofund[party.User.Id] = 0
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

	for _, party := range thing.Parties {
		neededfunds := tofund[party.User.Id]

		if party.User.ha.ID == "" {
			// doesn't exist on stellar, will create
			accountness := party.User.fundInitial(neededfunds + 20)
			accountsetups = append(accountsetups, accountness)
			homedomainess := b.SetOptions(
				b.SourceAccount{party.User.Address},
				b.HomeDomain("debtmoney.xyz"),
			)
			accountsetups = append(accountsetups, homedomainess)
		} else if neededfunds > 0 {
			accountness := party.User.fund(neededfunds)
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
UPDATE things SET txn = $1 WHERE id = $2
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
