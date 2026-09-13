package main

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

var ErrNotFound = errors.New("item not found")

type Item struct {
	ID          int       `json:"id"`
	Name        string    `json:"name"`
	Description string    `json:"description"`
	CreatedAt   time.Time `json:"created_at"`
}

type CreateItemRequest struct {
	Name        string `json:"name"`
	Description string `json:"description"`
}

type Repository interface {
	Create(ctx context.Context, req CreateItemRequest) (Item, error)
	List(ctx context.Context) ([]Item, error)
	GetByID(ctx context.Context, id int) (Item, error)
	Update(ctx context.Context, id int, req CreateItemRequest) (Item, error)
	Delete(ctx context.Context, id int) error
}

type pgRepository struct {
	pool *pgxpool.Pool
}

func newPgRepository(pool *pgxpool.Pool) Repository {
	return &pgRepository{pool: pool}
}

func (r *pgRepository) Create(ctx context.Context, req CreateItemRequest) (Item, error) {
	var item Item
	err := r.pool.QueryRow(ctx,
		`INSERT INTO items (name, description) VALUES ($1, $2) RETURNING id, name, description, created_at`,
		req.Name, req.Description,
	).Scan(&item.ID, &item.Name, &item.Description, &item.CreatedAt)
	return item, err
}

func (r *pgRepository) List(ctx context.Context) ([]Item, error) {
	rows, err := r.pool.Query(ctx, `SELECT id, name, description, created_at FROM items ORDER BY id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var items []Item
	for rows.Next() {
		var item Item
		if err := rows.Scan(&item.ID, &item.Name, &item.Description, &item.CreatedAt); err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

func (r *pgRepository) GetByID(ctx context.Context, id int) (Item, error) {
	var item Item
	err := r.pool.QueryRow(ctx,
		`SELECT id, name, description, created_at FROM items WHERE id = $1`, id,
	).Scan(&item.ID, &item.Name, &item.Description, &item.CreatedAt)
	if err != nil {
		return Item{}, fmt.Errorf("%w: id %d", ErrNotFound, id)
	}
	return item, nil
}

func (r *pgRepository) Update(ctx context.Context, id int, req CreateItemRequest) (Item, error) {
	var item Item
	err := r.pool.QueryRow(ctx,
		`UPDATE items SET name=$1, description=$2 WHERE id=$3 RETURNING id, name, description, created_at`,
		req.Name, req.Description, id,
	).Scan(&item.ID, &item.Name, &item.Description, &item.CreatedAt)
	if err != nil {
		return Item{}, fmt.Errorf("%w: id %d", ErrNotFound, id)
	}
	return item, nil
}

func (r *pgRepository) Delete(ctx context.Context, id int) error {
	result, err := r.pool.Exec(ctx, `DELETE FROM items WHERE id = $1`, id)
	if err != nil {
		return err
	}
	if result.RowsAffected() == 0 {
		return fmt.Errorf("%w: id %d", ErrNotFound, id)
	}
	return nil
}
