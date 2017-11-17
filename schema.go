package main

import (
	"github.com/graphql-go/graphql"
	"github.com/lucsky/cuid"
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

					ha, _ := h.LoadAccount(user.Address)
					user.ha = ha

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

					err := pg.Get(&asset.IssuerId,
						"SELECT id FROM users WHERE address = $1",
						asset.IssuerAddress)
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
		Type: thingType,
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

			return thing, nil
		},
	},
	"deleteThing": &graphql.Field{
		Type: thingType,
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

			return Thing{Id: thingId}, nil
		},
	},
	"publishThing": &graphql.Field{
		Type: thingType,
		Args: graphql.FieldConfigArgument{
			"thing_id": &graphql.ArgumentConfig{Type: graphql.String},
		},
		Resolve: func(p graphql.ResolveParams) (interface{}, error) {
			// anyone can publish what should already have been published
			// no auth. this was supposed to happen automatically on
			// the last confirmation.
			thingId := p.Args["thingg_id"].(string)
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

			return thing, err
		},
	},
	"confirmThing": &graphql.Field{
		Type: thingType,
		Args: graphql.FieldConfigArgument{
			"thing_id": &graphql.ArgumentConfig{Type: graphql.String},
			"confirm":  &graphql.ArgumentConfig{Type: graphql.Boolean},
		},
		Resolve: func(p graphql.ResolveParams) (interface{}, error) {
			userId, ok := p.Context.Value("userId").(string)
			if ok {
				_, err := ensureUser(userId)
				if err != nil {
					return nil, err
				}
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

			return thing, err
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
	Value string `json:"string"`
}

var rootQuery = graphql.ObjectConfig{Name: "RootQuery", Fields: queries}
var mutation = graphql.ObjectConfig{Name: "Mutation", Fields: mutations}

var schemaConfig = graphql.SchemaConfig{
	Query:    graphql.NewObject(rootQuery),
	Mutation: graphql.NewObject(mutation),
}
