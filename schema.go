package main

import (
	"errors"
	"strings"

	"github.com/graphql-go/graphql"
	"github.com/lucsky/cuid"
	b "github.com/stellar/go/build"
	"github.com/stellar/go/clients/horizon"
)

var queries = graphql.Fields{
	"user": &graphql.Field{
		Type: userType,
		Args: graphql.FieldConfigArgument{
			"id": &graphql.ArgumentConfig{Type: graphql.NewNonNull(graphql.String)},
		},
		Resolve: func(p graphql.ResolveParams) (interface{}, error) {
			var userId = p.Args["id"].(string)
			if userId == "me" {
				userId = p.Context.Value("userId").(string)
			}

			u, err := ensureUser(userId)
			if err != nil {
				return nil, err
			}

			// this will be used by subqueries on UserType
			ha, _ := h.LoadAccount(u.Address)
			u.ha = ha

			return u, nil
		},
	},
	"thing": &graphql.Field{
		Type: thingType,
		Args: graphql.FieldConfigArgument{
			"id": &graphql.ArgumentConfig{Type: graphql.NewNonNull(graphql.String)},
		},
		Resolve: func(p graphql.ResolveParams) (interface{}, error) {
			thingId := p.Args["id"].(string)

			var thing Thing
			err = pg.Get(&thing, `
SELECT `+thing.columns()+` FROM things
WHERE id = $1 LIMIT 1
        `, thingId)
			if err != nil {
				log.Error().Str("thing", thingId).Err(err).Msg("on get thing")
			}

			return thing, err
		},
	},
}

var userType = graphql.NewObject(
	graphql.ObjectConfig{
		Name: "UserType",
		Fields: graphql.Fields{
			"id":            &graphql.Field{Type: graphql.String},
			"address":       &graphql.Field{Type: graphql.String},
			"default_asset": &graphql.Field{Type: graphql.String},
			"balances": &graphql.Field{
				Type: graphql.NewList(balanceType),
				Resolve: func(p graphql.ResolveParams) (interface{}, error) {
					user := p.Source.(User)

					balances := make([]Balance, 0, len(user.ha.Balances))

					for _, b := range user.ha.Balances {
						if b.Asset.Type == "native" {
							continue // should we display this? no, probably not.
						}

						balances = append(balances, Balance{
							Asset: Asset{
								Code:          b.Asset.Code,
								IssuerAddress: b.Asset.Issuer,
							},
							Amount: b.Balance,
							Limit:  b.Limit,
						})
					}

					return balances, nil
				},
			},
			"things": &graphql.Field{
				Type: graphql.NewList(thingType),
				Resolve: func(p graphql.ResolveParams) (interface{}, error) {
					loggedUserId, ok := p.Context.Value("userId").(string)
					if !ok {
						return nil, nil
					}

					user := p.Source.(User)

					things := []Thing{}
					var err error
					if user.Id != loggedUserId {
						err = pg.Select(&things, `
SELECT `+(Thing{}).columns()+` FROM
  (SELECT thing_id, count(user_id)
   FROM parties
   WHERE user_id = $1 OR user_id = $2
   GROUP BY thing_id
  )x
INNER JOIN things ON thing_id = things.id
WHERE x.count >= 2
ORDER BY actual_date DESC
`, user.Id, loggedUserId)
					} else {
						err = pg.Select(&things, `
SELECT `+(Thing{}).columns()+` FROM things
INNER JOIN parties ON things.id = parties.thing_id
WHERE parties.user_id = $1
ORDER BY actual_date DESC
                    `, user.Id)

					}
					if err != nil {
						log.Error().Err(err).
							Str("logged", loggedUserId).
							Str("user", user.Id).
							Msg("on user things query")
						err = nil
					}

					return things, err
				},
			},
			"friends": &graphql.Field{
				Type: graphql.NewList(graphql.String),
				Resolve: func(p graphql.ResolveParams) (interface{}, error) {
					friends := []string{}

					user := p.Source.(User)
					loggedUserId, ok := p.Context.Value("userId").(string)
					if !ok || loggedUserId != user.Id {
						return friends, nil
					}

					err := pg.Select(&friends, `
SELECT friend FROM friends
WHERE main = $1
ORDER BY score DESC
                    `, user.Id)
					if err != nil {
						log.Warn().Err(err).Str("user", user.Id).
							Msg("failed to load friends")
					}

					return friends, nil
				},
			},
			"paths": &graphql.Field{
				Type: graphql.NewList(pathType),
				Resolve: func(p graphql.ResolveParams) (interface{}, error) {
					paths := []Path{}

					user := p.Source.(User)
					loggedUserId, ok := p.Context.Value("userId").(string)
					if !ok || loggedUserId == user.Id {
						return paths, nil
					}
					me, _ := getExistingUser(loggedUserId)

					assetCodes := map[string]bool{
						user.DefaultAsset: true,
					}
					for _, balance := range user.ha.Balances {
						if balance.Asset.Type != "native" {
							assetCodes[balance.Asset.Code] = true
						}
					}

					for code := range assetCodes {
						data, err := findPaths(
							me.Address,
							user.Address,
							Asset{code, user.Address, ""},
						)

						if err != nil {
							log.Debug().Err(err).Msg("failed to call /paths")
							continue
						}

						for _, p := range data.Embedded.Records {
							path := Path{
								Path: make([]Asset, len(p.Intermediaries)),
								Src:  Asset{p.SrcAssetCode, p.SrcAssetIssuer, ""},
								Dst:  Asset{p.DstAssetCode, p.DstAssetIssuer, ""},
							}

							for i, inter := range p.Intermediaries {
								path.Path[i] = Asset{inter.Code, inter.Issuer, ""}
							}
							paths = append(paths, path)
						}
					}

					return paths, nil
				},
			},
		},
	},
)

var pathType = graphql.NewObject(
	graphql.ObjectConfig{
		Name: "PathType",
		Fields: graphql.Fields{
			"src": &graphql.Field{
				Type: assetType,
				Resolve: func(p graphql.ResolveParams) (interface{}, error) {
					return p.Source.(Path).Src, nil
				},
			},
			"dst": &graphql.Field{
				Type: assetType,
				Resolve: func(p graphql.ResolveParams) (interface{}, error) {
					return p.Source.(Path).Dst, nil
				},
			},
			"path": &graphql.Field{Type: graphql.NewList(assetType)},
		},
	},
)

var balanceType = graphql.NewObject(
	graphql.ObjectConfig{
		Name: "BalanceType",
		Fields: graphql.Fields{
			"asset":  &graphql.Field{Type: assetType},
			"amount": &graphql.Field{Type: graphql.String},
			"limit":  &graphql.Field{Type: graphql.String},
		},
	},
)

var assetType = graphql.NewObject(
	graphql.ObjectConfig{
		Name: "AssetType",
		Fields: graphql.Fields{
			"code":           &graphql.Field{Type: graphql.String},
			"issuer_address": &graphql.Field{Type: graphql.String},
			"issuer_id": &graphql.Field{
				Type: graphql.String,
				Resolve: func(p graphql.ResolveParams) (interface{}, error) {
					asset := p.Source.(Asset)

					/* replace the code here with some faster call to an
					   in-memory hashmap of addresses->ids */

					err := pg.Get(
						&asset.IssuerId,
						"SELECT id FROM users WHERE address = $1",
						asset.IssuerAddress,
					)
					if err != nil {
						log.Info().
							Str("issuer", asset.IssuerAddress).
							Err(err).
							Msg("nothing found on asset issuer name query.")
					}
					return asset.IssuerId, nil
				},
			},
		},
	},
)

var thingType = graphql.NewObject(
	graphql.ObjectConfig{
		Name: "ThingType",
		Fields: graphql.Fields{
			"id":            &graphql.Field{Type: graphql.String},
			"created_at":    &graphql.Field{Type: graphql.String},
			"actual_date":   &graphql.Field{Type: graphql.String},
			"created_by":    &graphql.Field{Type: graphql.String},
			"name":          &graphql.Field{Type: graphql.String},
			"asset":         &graphql.Field{Type: graphql.String},
			"total_due":     &graphql.Field{Type: graphql.String},
			"total_due_set": &graphql.Field{Type: graphql.Boolean},
			"txn":           &graphql.Field{Type: graphql.String},
			"parties": &graphql.Field{
				Type: graphql.NewList(partyType),
				Resolve: func(p graphql.ResolveParams) (interface{}, error) {
					thing := p.Source.(Thing)
					err := thing.fillParties()
					return thing.Parties, err
				},
			},
			"publishable": &graphql.Field{Type: graphql.Boolean},
		},
	},
)

var partyType = graphql.NewObject(
	graphql.ObjectConfig{
		Name: "PartyType",
		Fields: graphql.Fields{
			"user_id":      &graphql.Field{Type: graphql.String},
			"account_name": &graphql.Field{Type: graphql.String},
			"thing_id":     &graphql.Field{Type: graphql.String},
			"paid":         &graphql.Field{Type: graphql.String},
			"due":          &graphql.Field{Type: graphql.String},
			"due_set":      &graphql.Field{Type: graphql.Boolean},
			"note":         &graphql.Field{Type: graphql.String},
			"added_by":     &graphql.Field{Type: graphql.String},
			"confirmed":    &graphql.Field{Type: graphql.Boolean},
		},
	},
)

var inputPartyType = graphql.NewInputObject(
	graphql.InputObjectConfig{
		Name: "InputPartyType",
		Fields: graphql.InputObjectConfigFieldMap{
			"account": &graphql.InputObjectFieldConfig{Type: graphql.String},
			"paid":    &graphql.InputObjectFieldConfig{Type: graphql.String},
			"due":     &graphql.InputObjectFieldConfig{Type: graphql.String},
		},
	},
)

var mutations = graphql.Fields{
	"setThing": &graphql.Field{
		Type: resultType,
		Args: graphql.FieldConfigArgument{
			"id":   &graphql.ArgumentConfig{Type: graphql.String},
			"date": &graphql.ArgumentConfig{Type: graphql.String},
			"name": &graphql.ArgumentConfig{Type: graphql.String},
			"asset": &graphql.ArgumentConfig{
				Type: graphql.NewNonNull(graphql.String),
			},
			"total_due": &graphql.ArgumentConfig{Type: graphql.String},
			"parties": &graphql.ArgumentConfig{
				Type: graphql.NewNonNull(graphql.NewList(
					graphql.NewNonNull(inputPartyType),
				)),
			},
		},
		Resolve: func(p graphql.ResolveParams) (interface{}, error) {
			userId, ok := p.Context.Value("userId").(string)
			if ok {
				_, err := ensureUser(userId)
				if err != nil {
					return nil, err
				}
			}

			thingId, _ := p.Args["id"].(string)
			date, _ := p.Args["date"].(string)
			name, _ := p.Args["name"].(string)
			total_due, _ := p.Args["total_due"].(string)
			asset := p.Args["asset"].(string)
			parties := p.Args["parties"].([]interface{})

			log.Info().
				Str("id", thingId).
				Str("date", date).
				Str("name", name).
				Str("asset", asset).
				Str("total_due", total_due).
				Int("nparties", len(parties)).
				Msg("creating thing")

			var thing Thing
			txn, err := pg.Beginx()
			if err != nil {
				return nil, err
			}
			defer txn.Rollback()
			if thingId != "" {
				err = deleteThing(txn, thingId)
				if err != nil {
					log.Warn().Err(err).Msg("failed to delete thing")
					return nil, err
				}
			}
			thingId = cuid.Slug()
			thing, err = insertThing(
				txn,
				thingId, date, userId, name, asset, total_due,
				parties)
			if err != nil {
				log.Warn().Err(err).Msg("failed to insert thing")
				return nil, err
			}

			err = txn.Commit()
			if err != nil {
				log.Warn().Err(err).Msg("failed to commit thing transaction")
				return nil, err
			}

			return thing.Id, nil
		},
	},
	"deleteThing": &graphql.Field{
		Type: resultType,
		Args: graphql.FieldConfigArgument{
			"thingId": &graphql.ArgumentConfig{Type: graphql.String},
		},
		Resolve: func(p graphql.ResolveParams) (interface{}, error) {
			thingId := p.Args["thingId"].(string)

			txn, err := pg.Beginx()
			if err != nil {
				return nil, err
			}
			defer txn.Rollback()

			if thingId != "" {
				err = deleteThing(txn, thingId)
				if err != nil {
					log.Warn().Err(err).Msg("failed to delete thing")
					return nil, err
				}
			}

			err = txn.Commit()
			if err != nil {
				log.Warn().Err(err).Msg("failed to commit thing transaction")
			}

			return thingId, nil
		},
	},
	"publishThing": &graphql.Field{
		Type: resultType,
		Args: graphql.FieldConfigArgument{
			"thing_id": &graphql.ArgumentConfig{Type: graphql.String},
		},
		Resolve: func(p graphql.ResolveParams) (interface{}, error) {
			// anyone can publish what should already have been published
			// no auth. this was supposed to happen automatically on
			// the last confirmation.
			thingId := p.Args["thing_id"].(string)
			var thing Thing
			err = pg.Get(&thing, `
SELECT `+thing.columns()+` FROM things
WHERE id = $1 LIMIT 1
        `, thingId)
			if err != nil {
				log.Error().Str("thing", thingId).Err(err).Msg("on get thing")
			}

			if thing.Publishable {
				_, err = thing.publish()
			}

			return thing.Transaction, err
		},
	},
	"confirmThing": &graphql.Field{
		Type: resultType,
		Args: graphql.FieldConfigArgument{
			"thing_id": &graphql.ArgumentConfig{Type: graphql.String},
			"confirm":  &graphql.ArgumentConfig{Type: graphql.Boolean},
		},
		Resolve: func(p graphql.ResolveParams) (interface{}, error) {
			userId, ok := p.Context.Value("userId").(string)
			if !ok {
				return nil, errors.New("no-logged-user")
			}
			_, err := ensureUser(userId)
			if err != nil {
				return nil, err
			}

			thingId := p.Args["thing_id"].(string)
			confirm := p.Args["confirm"].(bool)

			thing, published, err := confirmThing(thingId, userId, confirm)
			if err != nil {
				return nil, err
			}

			log.Info().
				Str("thing", thingId).
				Err(err).
				Bool("published", published).
				Msg("thing confirmation")

			return thing.Transaction, err
		},
	},
	"sendPayment": &graphql.Field{
		Type: resultType,
		Args: graphql.FieldConfigArgument{
			"dst_user":    &graphql.ArgumentConfig{Type: graphql.String},
			"dst_code":    &graphql.ArgumentConfig{Type: graphql.String},
			"dst_address": &graphql.ArgumentConfig{Type: graphql.String},
			"src_code":    &graphql.ArgumentConfig{Type: graphql.String},
			"src_address": &graphql.ArgumentConfig{Type: graphql.String},
			"amount":      &graphql.ArgumentConfig{Type: graphql.String},
		},
		Resolve: func(p graphql.ResolveParams) (interface{}, error) {
			userId, ok := p.Context.Value("userId").(string)
			if !ok {
				return nil, errors.New("no-logged-user")
			}

			payer, err := getExistingUser(userId)
			if err != nil {
				return nil, err
			}
			receiver, err := getExistingUser(p.Args["dst_user"].(string))
			if err != nil {
				return nil, err
			}

			operations := []b.TransactionMutator{}
			seeds := []string{s.SourceSeed}

			// the receiving user should be an existing stellar account.
			_, err = h.LoadAccount(receiver.Address)
			if err != nil {
				if herr, ok := err.(*horizon.Error); ok && herr.Response.StatusCode == 404 {
					// if it is not, we must create it.
					operations = append(
						operations,
						receiver.fundInitial(20),
						b.SetOptions(
							b.SourceAccount{receiver.Address},
							b.HomeDomain("debtmoney.xyz"),
						),
					)
					seeds = append(seeds, receiver.Seed)
				} else {
					return nil, err
				}
			}

			// now we proceed to the payment
			payment := b.Payment(
				b.SourceAccount{payer.Address},
				b.CreditAmount{
					Code:   p.Args["dst_code"].(string),
					Issuer: p.Args["dst_address"].(string),
					Amount: p.Args["amount"].(string),
				},
				b.Destination{receiver.Address},
				b.PayWith(
					b.Asset{
						Code:   p.Args["src_code"].(string),
						Issuer: p.Args["src_address"].(string),
						Native: false,
					},
					p.Args["amount"].(string),
				),
			)
			operations = append(operations, payment)
			seeds = append(seeds, payer.Seed)

			log.Info().Msg("publishing a path payment")
			tx := createStellarTransaction()

			tx.Mutate(b.MemoText{"user-initiated"})
			tx.Mutate(operations...)

			hash, err := commitStellarTransaction(tx, seeds...)
			if err != nil {
				if herr, ok := err.(*horizon.Error); ok {
					h, metaerr := herr.ResultCodes()
					if metaerr != nil {
						return nil, err
					}
					return nil, errors.New(
						h.TransactionCode + ": [" + strings.Join(h.OperationCodes, ",") + "]",
					)
				}
				return nil, err
			}

			return Result{hash}, nil
		},
	},
}

var resultType = graphql.NewObject(
	graphql.ObjectConfig{
		Name: "ResultType",
		Fields: graphql.Fields{
			"value": &graphql.Field{Type: graphql.String},
		},
	},
)

type Result struct {
	Value string `json:"value"`
}

var rootQuery = graphql.ObjectConfig{Name: "RootQuery", Fields: queries}
var mutation = graphql.ObjectConfig{Name: "Mutation", Fields: mutations}

var schemaConfig = graphql.SchemaConfig{
	Query:    graphql.NewObject(rootQuery),
	Mutation: graphql.NewObject(mutation),
}
