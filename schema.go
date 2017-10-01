package main

import (
	"errors"

	"github.com/graphql-go/graphql"
)

var queries = graphql.Fields{
	"user": &graphql.Field{
		Type: userType,
		Args: graphql.FieldConfigArgument{
			"id": &graphql.ArgumentConfig{Type: graphql.NewNonNull(graphql.String)},
		},
		Resolve: func(p graphql.ResolveParams) (interface{}, error) {
			if p.Args["id"].(string) == "me" {
				userId, ok := p.Context.Value("userId").(string)
				if ok {
					return ensureUser(userId)
				}
			}
			return nil, nil
		},
	},
}

var userType = graphql.NewObject(
	graphql.ObjectConfig{
		Name: "UserType",
		Fields: graphql.Fields{
			"id":      &graphql.Field{Type: graphql.String},
			"address": &graphql.Field{Type: graphql.String},
			"balances": &graphql.Field{
				Type: graphql.NewList(balanceType),
				Resolve: func(p graphql.ResolveParams) (interface{}, error) {
					user := p.Source.(User)
					balances := make([]Balance, len(user.ha.Balances)-1)

					for i, b := range user.ha.Balances {
						var assetName string
						if b.Asset.Type == "native" {
							continue
						} else {
							issuerName := b.Asset.Issuer
							err := pg.Get(&issuerName,
								"SELECT name || '@' || source FROM userounts WHERE public = $1",
								b.Asset.Issuer)
							if err != nil {
								log.Error().Err(err).Msg("on asset issuer name query.")
							}
							assetName = b.Asset.Code + "#" + issuerName
						}

						balances[i] = Balance{
							Asset:  assetName,
							Amount: b.Balance,
						}
					}

					return balances, nil
				},
			},
		},
	},
)

var balanceType = graphql.NewObject(
	graphql.ObjectConfig{
		Name: "BalanceType",
		Fields: graphql.Fields{
			"asset":  &graphql.Field{Type: graphql.String},
			"amount": &graphql.Field{Type: graphql.String},
		},
	},
)

var mutations = graphql.Fields{
	"declareDebt": &graphql.Field{
		Type: resultType,
		Args: graphql.FieldConfigArgument{
			"creditor": &graphql.ArgumentConfig{Type: graphql.String},
			"asset":    &graphql.ArgumentConfig{Type: graphql.String},
			"amount":   &graphql.ArgumentConfig{Type: graphql.String},
		},
		Resolve: func(p graphql.ResolveParams) (interface{}, error) {
			userId, ok := p.Context.Value("userId").(string)
			if !ok {
				return nil, errors.New("user not logged")
			}
			me, err := ensureUser(userId)
			if err != nil {
				return nil, err
			}

			creditor := p.Args["creditor"].(string)
			asset := p.Args["asset"].(string)
			amount := p.Args["amount"].(string)

			log.Info().
				Str("from", me.Id).
				Str("to", creditor).
				Str("asset", asset).
				Str("amount", amount).
				Msg("looking up creditor")

			look, err := lookupUser(creditor)
			if err != nil {
				return nil, err
			}

			var cred User
			if look.Id != "" {
				cred, err = ensureUser(look.Id)
				if err != nil {
					return nil, err
				}
			}

			debt, err := me.simpleDebt(me.Id, creditor, asset, amount)
			if err != nil {
				return nil, err
			}

			log.Info().Int("id", debt.Id).Msg("debt created, should we confirm?")

			if look.Id != "" {
				debt.From = me
				debt.To = cred
				err = debt.Confirm(look.Id)
			}

			return nil, err
		},
	},
}

var resultType = graphql.NewObject(
	graphql.ObjectConfig{
		Name: "ResultType",
		Fields: graphql.Fields{
			"ok":    &graphql.Field{Type: graphql.Boolean},
			"value": &graphql.Field{Type: graphql.String},
			"error": &graphql.Field{Type: graphql.String},
		},
	},
)

var rootQuery = graphql.ObjectConfig{Name: "RootQuery", Fields: queries}
var mutation = graphql.ObjectConfig{Name: "Mutation", Fields: mutations}

var schemaConfig = graphql.SchemaConfig{
	Query:    graphql.NewObject(rootQuery),
	Mutation: graphql.NewObject(mutation),
}
