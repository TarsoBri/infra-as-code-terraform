package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

func main() {
	port := os.Getenv("APP_PORT")
	if port == "" {
		port = "8080"
	}

	pool, err := pgxpool.New(context.Background(), buildDSN())
	if err != nil {
		log.Fatalf("cannot connect to database: %v", err)
	}
	defer pool.Close()

	if _, err := pool.Exec(context.Background(), `
		CREATE TABLE IF NOT EXISTS items (
			id          SERIAL PRIMARY KEY,
			name        TEXT NOT NULL,
			description TEXT,
			created_at  TIMESTAMPTZ DEFAULT NOW()
		)
	`); err != nil {
		log.Fatalf("cannot create items table: %v", err)
	}

	h := &handler{repo: newPgRepository(pool)}
	r := chi.NewRouter()
	r.Get("/health", h.health)
	r.Post("/items", h.create)
	r.Get("/items", h.list)
	r.Get("/items/{id}", h.get)
	r.Put("/items/{id}", h.update)
	r.Delete("/items/{id}", h.delete)

	log.Printf("listening on :%s (env=%s)", port, os.Getenv("ENV"))
	log.Fatal(http.ListenAndServe(":"+port, r))
}

func buildDSN() string {
	return fmt.Sprintf(
		"postgres://%s:%s@%s:%s/%s?sslmode=require",
		os.Getenv("DB_USERNAME"),
		os.Getenv("DB_PASSWORD"),
		os.Getenv("DB_HOST"),
		os.Getenv("DB_PORT"),
		os.Getenv("DB_NAME"),
	)
}
