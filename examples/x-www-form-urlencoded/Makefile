SHELL:=bash

all: testsrv-image test-setup test test-teardown

.PHONY: testsrv-image
testsrv-image:
	docker build -t testsrv testsrv/

.PHONY: test-setup
test-setup:
	docker-compose up -d

.PHONY: test-teardown
test-teardown:
	docker-compose logs
	docker-compose down

.PHONY: test
test:
