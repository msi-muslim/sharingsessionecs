package router

import (
	"net/http"
	"prabogo-app/internal/handler"
)

func New() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/health", handler.HealthCheck)
	mux.HandleFunc("/", handler.Home)
	return mux
}
