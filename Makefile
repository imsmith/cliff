.PHONY: build-base build-dev build-obsv build-full build-all test clean

build-base:
	docker build -t cliff/base:latest -f build/Dockerfile.base .

build-dev: build-base
	docker build -t cliff/dev:latest -f build/Dockerfile.dev .

build-obsv: build-base
	docker build -t cliff/obsv:latest -f build/Dockerfile.obsv .

build-full: build-dev
	docker build -t cliff/full:latest -f build/Dockerfile.full .

build-all: build-base build-dev build-obsv build-full

test:
	@bash test/smoke.sh

clean:
	docker rmi -f cliff/full:latest cliff/obsv:latest cliff/dev:latest cliff/base:latest 2>/dev/null || true
