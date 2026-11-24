.PHONY: build up down logs test

build:
	docker compose build

up:
	docker compose up --build -d

down:
	docker compose down

logs:
	docker compose logs -f api

test:
	python3 scripts/smoke.py
