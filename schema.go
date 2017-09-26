package main

import (
	"errors"

	"github.com/graphql-go/graphql"
	"github.com/kr/pretty"
	"github.com/stellar/go/clients/horizon"
)

var queries = graphql.Fields{
	"me": &graphql.Field{
		Type: userType,
		Resolve: func(p graphql.ResolveParams) (interface{}, error) {
			user, ok := p.Context.Value("user").(string)
			if ok {
				name, source, err := decoupleNameSource(user)
				if err != nil {
					return nil, err
				}
				return ensureAccount(name, source)
			}
			return nil, nil
		},
	},
}

var userType = graphql.NewObject(
	graphql.ObjectConfig{
		Name: "UserType",
		Fields: graphql.Fields{
			"name":   &graphql.Field{Type: graphql.String},
			"source": &graphql.Field{Type: graphql.String},
			"public": &graphql.Field{Type: graphql.String},
			"balances": &graphql.Field{
				Type: graphql.NewList(balanceType),
				Resolve: func(p graphql.ResolveParams) (interface{}, error) {
					acc := p.Source.(Account)
					balances := make([]Balance, len(acc.Balances)-1)

					for i, b := range acc.Balances {
						var assetName string
						if b.Asset.Type == "native" {
							continue
						} else {
							issuerName := b.Asset.Issuer
							err := pg.Get(&issuerName,
								"SELECT name || '@' || source FROM accounts WHERE public = $1",
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
			user, ok := p.Context.Value("user").(string)
			if !ok {
				return nil, errors.New("user not logged")
			}
			name, source, err := decoupleNameSource(user)
			if err != nil {
				return nil, err
			}
			me, err := ensureAccount(name, source)
			if err != nil {
				return nil, err
			}
			l := log.With().Timestamp().
				Str("from", me.Name+"@"+me.Source).
				Logger()

			creditor := p.Args["creditor"].(string)
			name, source, err = decoupleNameSource(creditor)
			if err != nil {
				return nil, err
			}
			cred, err := ensureAccount(name, source)
			if err != nil {
				return nil, err
			}
			l = l.With().Timestamp().
				Str("to", cred.Name+"@"+cred.Source).
				Logger()

			asset := p.Args["asset"].(string)
			amount := p.Args["amount"].(string)
			l = l.With().Timestamp().
				Str("asset", asset).
				Str("amount", amount).
				Logger()

			l.Info().Msg("adjusting trustline")
			err = cred.trust(me, asset, amount)
			if err != nil {
				if herr, ok := err.(*horizon.Error); ok {
					c, _ := herr.ResultCodes()
					pretty.Log(c)
				}
				return nil, err
			}

			l.Info().Msg("transfering asset")
			err = me.makeDebt(cred, asset, amount)
			if err != nil {
				if herr, ok := err.(*horizon.Error); ok {
					c, _ := herr.ResultCodes()
					pretty.Log(c)
				}
				return nil, err
			}

			return nil, nil
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
