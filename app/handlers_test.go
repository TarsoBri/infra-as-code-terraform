package main

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/go-chi/chi/v5"
)

// mockRepo is an in-memory implementation of Repository used only in tests
type mockRepo struct {
	items  map[int]Item
	nextID int
}

func newMockRepo() *mockRepo {
	return &mockRepo{items: make(map[int]Item), nextID: 1}
}

func (m *mockRepo) Create(_ context.Context, req CreateItemRequest) (Item, error) {
	item := Item{ID: m.nextID, Name: req.Name, Description: req.Description}
	m.items[m.nextID] = item
	m.nextID++
	return item, nil
}

func (m *mockRepo) List(_ context.Context) ([]Item, error) {
	result := make([]Item, 0, len(m.items))
	for _, item := range m.items {
		result = append(result, item)
	}
	return result, nil
}

func (m *mockRepo) GetByID(_ context.Context, id int) (Item, error) {
	item, ok := m.items[id]
	if !ok {
		return Item{}, ErrNotFound
	}
	return item, nil
}

func (m *mockRepo) Update(_ context.Context, id int, req CreateItemRequest) (Item, error) {
	if _, ok := m.items[id]; !ok {
		return Item{}, ErrNotFound
	}
	item := Item{ID: id, Name: req.Name, Description: req.Description}
	m.items[id] = item
	return item, nil
}

func (m *mockRepo) Delete(_ context.Context, id int) error {
	if _, ok := m.items[id]; !ok {
		return ErrNotFound
	}
	delete(m.items, id)
	return nil
}

func newTestRouter(repo Repository) http.Handler {
	h := &handler{repo: repo}
	r := chi.NewRouter()
	r.Get("/health", h.health)
	r.Post("/items", h.create)
	r.Get("/items", h.list)
	r.Get("/items/{id}", h.get)
	r.Put("/items/{id}", h.update)
	r.Delete("/items/{id}", h.delete)
	return r
}

func TestHealth(t *testing.T) {
	r := newTestRouter(newMockRepo())
	w := httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/health", nil))
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
}

func TestCreateAndGetItem(t *testing.T) {
	r := newTestRouter(newMockRepo())

	body, _ := json.Marshal(CreateItemRequest{Name: "book", Description: "a novel"})
	w := httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodPost, "/items", bytes.NewReader(body)))
	if w.Code != http.StatusCreated {
		t.Fatalf("create: expected 201, got %d", w.Code)
	}

	var created Item
	json.NewDecoder(w.Body).Decode(&created)
	if created.Name != "book" {
		t.Fatalf("expected name 'book', got %q", created.Name)
	}

	w2 := httptest.NewRecorder()
	r.ServeHTTP(w2, httptest.NewRequest(http.MethodGet, "/items/1", nil))
	if w2.Code != http.StatusOK {
		t.Fatalf("get: expected 200, got %d", w2.Code)
	}
}

func TestListItems(t *testing.T) {
	repo := newMockRepo()
	repo.Create(context.Background(), CreateItemRequest{Name: "a"})
	repo.Create(context.Background(), CreateItemRequest{Name: "b"})

	r := newTestRouter(repo)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/items", nil))
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	var items []Item
	json.NewDecoder(w.Body).Decode(&items)
	if len(items) != 2 {
		t.Fatalf("expected 2 items, got %d", len(items))
	}
}

func TestUpdateItem(t *testing.T) {
	repo := newMockRepo()
	repo.Create(context.Background(), CreateItemRequest{Name: "old"})

	r := newTestRouter(repo)
	body, _ := json.Marshal(CreateItemRequest{Name: "new"})
	w := httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodPut, "/items/1", bytes.NewReader(body)))
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	var updated Item
	json.NewDecoder(w.Body).Decode(&updated)
	if updated.Name != "new" {
		t.Fatalf("expected name 'new', got %q", updated.Name)
	}
}

func TestDeleteItem(t *testing.T) {
	repo := newMockRepo()
	repo.Create(context.Background(), CreateItemRequest{Name: "to-delete"})

	r := newTestRouter(repo)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodDelete, "/items/1", nil))
	if w.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d", w.Code)
	}
}
