package main

import (
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	_ "github.com/lib/pq"

	"github.com/fiatjaf/uud-go"
	"github.com/gorilla/mux"
	"github.com/gorilla/sessions"
	"github.com/jmoiron/sqlx"
	"github.com/kelseyhightower/envconfig"
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
var sessionStore *sessions.CookieStore
var log = zerolog.New(os.Stderr).Output(zerolog.ConsoleWriter{Out: os.Stderr})

func main() {
	err = envconfig.Process("", &s)
	if err != nil {
		log.Fatal().Err(err).Msg("couldn't process envconfig.")
	}

	uud.HOST = "https://cantillon.alhur.es:6336"
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

	// define routes
	router = mux.NewRouter()

	api := router.PathPrefix("/_").Subrouter()
	api.Path("/user/{id}").Methods("GET").HandlerFunc(getUser)
	api.Path("/debt").Methods("POST").HandlerFunc(createDebt)

	router.PathPrefix("/app/").Methods("GET").HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			if r.URL.Path[len(r.URL.Path)-5:] == ".html" {
				http.ServeFile(w, r, "./index.html")
				return
			}
			http.ServeFile(w, r, "./client/"+r.URL.Path[5:])
		},
	)
	router.Path("/auth/callback").Methods("GET").HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			code := r.URL.Query().Get("code")

			user, err := uud.VerifyAuth(code)

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

				// we now check if this user owns one of the accounts
				// we have registered here (like if some debtmoney user
				// has declared a debt with fulano@twitter we want to
				// know if this new logged user owns fulano@twitter and
				// redirect these debts to him).
				params := make([]interface{}, len(user.Accounts)+1)
				params[0] = user.Id
				accvars := make([]string, len(user.Accounts))
				for i, account := range user.Accounts {
					params[i+1] = account.Account
					accvars[i] = "$" + strconv.Itoa(i+2)
				}
				vars := strings.Join(accvars, ",")

				_, err = pg.Exec(`
UPDATE records SET description = CASE
  WHEN description->>'from' IN (`+vars+`) THEN jsonb_set(description, '{from}', to_jsonb($1::text))
  WHEN description->>'to' IN (`+vars+`) THEN jsonb_set(description, '{to}', to_jsonb($1::text))
END
  WHERE description->>'from' IN (`+vars+`)
     OR description->>'to' IN (`+vars+`)
                `, params...)
				if err != nil {
					log.Error().Err(err).Str("user", user.Id).
						Msg("failed to update accounts to user")
				}

				// finally we set up the session
				session.Values["userId"] = user.Id
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

	// start the server
	log.Info().Str("port", os.Getenv("PORT")).Msg("listening.")
	graceful.Run(":"+os.Getenv("PORT"), 10*time.Second, router)
}
