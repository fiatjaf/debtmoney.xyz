package main

import (
	"context"
	"io/ioutil"
	"net/http"
	"os"
	"time"

	_ "github.com/lib/pq"

	"github.com/gorilla/mux"
	"github.com/gorilla/sessions"
	"github.com/graphql-go/graphql"
	"github.com/graphql-go/handler"
	"github.com/jmoiron/sqlx"
	"github.com/kelseyhightower/envconfig"
	"github.com/rs/zerolog"
	"github.com/stellar/go/clients/horizon"
	"gopkg.in/tylerb/graceful.v1"
)

type Settings struct {
	SourceAddress string `envconfig:"SOURCE_ADDRESS"`
	SourceSeed    string `envconfig:"SOURCE_SEED"`
	PostgresURL   string `envconfig:"DATABASE_URL"`
	SecretKey     string `envconfig:"SECRET_KEY"`
	ServiceURL    string `envconfig:"SERVICE_URL"`
}

var err error
var s Settings
var pg *sqlx.DB
var router *mux.Router
var schema graphql.Schema
var testnet = horizon.DefaultTestNetClient
var mainnet = horizon.DefaultPublicNetClient
var sessionStore *sessions.CookieStore
var log = zerolog.New(os.Stderr).Output(zerolog.ConsoleWriter{Out: os.Stderr})

func main() {
	err = envconfig.Process("", &s)
	if err != nil {
		log.Fatal().Err(err).Msg("couldn't process envconfig.")
	}

	zerolog.SetGlobalLevel(zerolog.DebugLevel)

	// cookie store
	sessionStore = sessions.NewCookieStore([]byte(s.SecretKey))

	// postgres client
	pg, err = sqlx.Open("postgres", s.PostgresURL)
	if err != nil {
		log.Fatal().Err(err).Str("uri", s.PostgresURL).Msg("failed to connect to pg")
	}

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
	router.Path("/auth/callback").Methods("GET").HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			code := r.URL.Query().Get("code")

			resp, err := http.Post(
				"https://unified-users-database.herokuapp.com/verify/"+code,
				"text/plain",
				nil,
			)
			if err != nil {
				http.Error(w, err.Error(), 503)
				return
			}

			content, err := ioutil.ReadAll(resp.Body)
			if err != nil {
				http.Error(w, err.Error(), 500)
				return
			}

			userId := string(content)
			if userId == "" {
				http.Error(w, "invalid authorization", 401)
				return
			} else {
				session, err := sessionStore.Get(r, "auth-session")
				if err != nil {
					http.Error(w, err.Error(), 500)
					return
				}

				session.Values["userId"] = userId
				session.Save(r, w)
				http.Redirect(w, r, "/app/", 302)
			}
		},
	)
	router.Path("/_graphql").Methods("POST").HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			ctx := context.TODO()

			session, err := sessionStore.Get(r, "auth-session")
			if err != nil {
				http.Error(w, err.Error(), 500)
				return
			}

			if userId, ok := session.Values["userId"]; ok {
				ctx = context.WithValue(ctx, "userId", userId)
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
