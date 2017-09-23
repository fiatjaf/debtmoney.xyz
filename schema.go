package main

import (
	"github.com/graphql-go/graphql"
)

var queries = graphql.Fields{
	"me": &graphql.Field{
		Type: userType,
		Resolve: func(p graphql.ResolveParams) (interface{}, error) {
			user, ok := p.Context.Value("user").(string)
			if ok {
				return User{Name: user}, nil
			}
			return nil, nil
		},
	},
}

var mutations = graphql.Fields{
	"donothing": &graphql.Field{
		Type: userType,
		Resolve: func(p graphql.ResolveParams) (interface{}, error) {
			return nil, nil
		},
	},
}

var rootQuery = graphql.ObjectConfig{Name: "RootQuery", Fields: queries}
var mutation = graphql.ObjectConfig{Name: "Mutation", Fields: mutations}

var schemaConfig = graphql.SchemaConfig{
	Query:    graphql.NewObject(rootQuery),
	Mutation: graphql.NewObject(mutation),
}

var userType = graphql.NewObject(
	graphql.ObjectConfig{
		Name: "UserType",
		Fields: graphql.Fields{
			"name": &graphql.Field{Type: graphql.String},
		},
	},
)

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
