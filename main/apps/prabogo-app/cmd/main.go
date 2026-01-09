package main

import (
	"log"
	"prabogo-app/internal/app"
)

func main() {
	app := app.New()
	log.Println("🚀 Prabogo v1 service running on :8080")
	log.Fatal(app.Run())
}
