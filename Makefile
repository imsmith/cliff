VERSION ?= 0.3.0
REGISTRY ?= ghcr.io/imsmith

.PHONY: build-base build-dev build-obsv build-full build-all \
        push-base push-dev push-obsv push-full push-all \
        test clean

build-base:
	docker build -t $(REGISTRY)/cliff-base:$(VERSION) -t $(REGISTRY)/cliff-base:latest -t cliff-base:$(VERSION) -f build/Dockerfile.base .

build-dev: build-base
	docker build -t $(REGISTRY)/cliff-dev:$(VERSION) -t $(REGISTRY)/cliff-dev:latest -t cliff-dev:$(VERSION) -f build/Dockerfile.dev .

build-obsv: build-base
	docker build -t $(REGISTRY)/cliff-obsv:$(VERSION) -t $(REGISTRY)/cliff-obsv:latest -t cliff-obsv:$(VERSION) -f build/Dockerfile.obsv .

build-full: build-dev
	docker build -t $(REGISTRY)/cliff-full:$(VERSION) -t $(REGISTRY)/cliff-full:latest -t cliff-full:$(VERSION) -f build/Dockerfile.full .

build-all: build-base build-dev build-obsv build-full

push-base:
	docker push $(REGISTRY)/cliff-base:$(VERSION)
	docker push $(REGISTRY)/cliff-base:latest

push-dev:
	docker push $(REGISTRY)/cliff-dev:$(VERSION)
	docker push $(REGISTRY)/cliff-dev:latest

push-obsv:
	docker push $(REGISTRY)/cliff-obsv:$(VERSION)
	docker push $(REGISTRY)/cliff-obsv:latest

push-full:
	docker push $(REGISTRY)/cliff-full:$(VERSION)
	docker push $(REGISTRY)/cliff-full:latest

push-all: push-base push-dev push-obsv push-full

test:
	@bash test/smoke.sh

build-egress:
	docker build -f images/egress/Dockerfile -t cliff-egress:0.3.0 .

clean:
	docker rmi -f $(REGISTRY)/cliff-full:$(VERSION) $(REGISTRY)/cliff-full:latest \
		$(REGISTRY)/cliff-obsv:$(VERSION) $(REGISTRY)/cliff-obsv:latest \
		$(REGISTRY)/cliff-dev:$(VERSION) $(REGISTRY)/cliff-dev:latest \
		$(REGISTRY)/cliff-base:$(VERSION) $(REGISTRY)/cliff-base:latest 2>/dev/null || true
