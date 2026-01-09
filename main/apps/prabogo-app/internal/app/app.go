package app

import (
	"net/http"
	"prabogo-app/internal/router"
)

type App struct {
	server *http.Server
}

func New() *App {
	r := router.New()

	return &App{
		server: &http.Server{
			Addr:    ":8080",
			Handler: r,
		},
	}
}

func (a *App) Run() error {
	return a.server.ListenAndServe()
}
