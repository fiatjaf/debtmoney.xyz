package main

import (
	"context"
	"encoding/base64"
	"net/http"
	"os"
	"time"

	"github.com/gorilla/mux"
	"github.com/graphql-go/graphql"
	"github.com/graphql-go/handler"
	"github.com/kelseyhightower/envconfig"
	"github.com/rs/zerolog"
	"gopkg.in/tylerb/graceful.v1"
)

type Settings struct {
}

var err error
var s Settings
var router *mux.Router
var schema graphql.Schema
var log = zerolog.New(os.Stderr).Output(zerolog.ConsoleWriter{Out: os.Stderr})

func main() {
	err = envconfig.Process("", &s)
	if err != nil {
		log.Fatal().Err(err).Msg("couldn't process envconfig.")
	}

	zerolog.SetGlobalLevel(zerolog.DebugLevel)

	// graphql schema
	schema, err = graphql.NewSchema(schemaConfig)
	if err != nil {
		log.Fatal().Err(err).Msg("failed to create graphql schema")
	}
	handler := handler.New(&handler.Config{Schema: &schema})

	// define routes
	router = mux.NewRouter()

	router.PathPrefix("/app/").Methods("GET").HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			if r.URL.Path[len(r.URL.Path)-5:] == ".html" {
				http.ServeFile(w, r, "./index.html")
				return
			}
			http.ServeFile(w, r, "."+r.URL.Path)
		},
	)
	router.Path("/_graphql").Methods("POST").HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			ctx := context.TODO()

			m, _ := base64.StdEncoding.DecodeString(r.Header.Get("Authorization"))
			user, valid, err := keybaseAuth(string(m))
			if err == nil && valid {
				ctx = context.WithValue(ctx, "user", user)
			}

			w.Header().Set("Content-Type", "application/json")
			handler.ContextHandler(ctx, w, r)
		},
	)
	router.Path("/").Methods("GET").HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			http.ServeFile(w, r, "./landing.html")
		},
	)

	// start the server
	log.Info().Str("port", os.Getenv("PORT")).Msg("listening.")
	graceful.Run(":"+os.Getenv("PORT"), 10*time.Second, router)
}
