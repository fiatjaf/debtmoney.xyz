package main

import (
	"context"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/graphql-go/graphql"
	"github.com/graphql-go/handler"
	_ "github.com/lib/pq"

	"github.com/fiatjaf/accountd"
	"github.com/gorilla/mux"
	"github.com/gorilla/sessions"
	"github.com/jmoiron/sqlx"
	"github.com/kelseyhightower/envconfig"
	"github.com/rs/cors"
	"github.com/rs/zerolog"
	"github.com/stellar/go/build"
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
var h *horizon.Client
var n build.Network
var pg *sqlx.DB
var router *mux.Router
var schema graphql.Schema
var sessionStore *sessions.CookieStore
var log = zerolog.New(os.Stderr).Output(zerolog.ConsoleWriter{Out: os.Stderr})

func main() {
	err = envconfig.Process("", &s)
	if err != nil {
		log.Fatal().Err(err).Msg("couldn't process envconfig.")
	}

	accountd.HOST = "https://cantillon.alhur.es:6336"
	zerolog.SetGlobalLevel(zerolog.DebugLevel)

	// cookie store
	sessionStore = sessions.NewCookieStore([]byte(s.SecretKey))

	// stellar clients
	h = horizon.DefaultTestNetClient
	n = build.TestNetwork

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
			if len(strings.Split(r.URL.Path, ".")) == 1 {
				http.ServeFile(w, r, "./client/index.html")
				return
			}
			http.ServeFile(w, r, "./client/"+r.URL.Path[5:])
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

	router.Path("/auth/callback").Methods("GET").HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			code := r.URL.Query().Get("code")

			accountduser, err := accountd.VerifyAuth(code)

			if err != nil {
				log.Error().Err(err).Msg("invalid authorization")
				http.Error(w, "invalid authorization", 401)
				return
			} else {
				session, err := sessionStore.Get(r, "auth-session")
				if err != nil {
					http.Error(w, err.Error(), 500)
					return
				}

				ensureUser(accountduser.Id)

				// we now check if this user owns one of the accounts
				// we have registered here (like if some debtmoney user
				// has declared a debt with fulano@twitter we want to
				// know if this new logged user owns fulano@twitter and
				// redirect these debts to him).
				params := make([]interface{}, len(accountduser.Accounts)+1)
				params[0] = accountduser.Id
				accvars := make([]string, len(accountduser.Accounts)+1)
				accvars[0] = "$1"
				for i, account := range accountduser.Accounts {
					accvars[i+1] = "$" + strconv.Itoa(i+2)
					params[i+1] = account.Account
				}
				vars := strings.Join(accvars, ",")

				_, err = pg.Exec(`
UPDATE parties SET user_id = $1
WHERE account_name IN (`+vars+`)
                `, params...)
				if err != nil {
					log.Error().Err(err).Str("user", accountduser.Id).
						Msg("failed to update parties records to user")
				}

				// finally we set up the session
				session.Values["userId"] = accountduser.Id
				session.Save(r, w)
				http.Redirect(w, r, "/app/", 302)
			}
		},
	)
	router.Path("/").Methods("GET").HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			http.ServeFile(w, r, "./landing.html")
		},
	)

	c := cors.New(cors.Options{
		AllowCredentials: true,
		AllowOriginFunc:  func(origin string) bool { return true },
	})

	// start the server
	log.Info().Str("port", os.Getenv("PORT")).Msg("listening.")
	graceful.Run(":"+os.Getenv("PORT"), 10*time.Second, c.Handler(router))
}
