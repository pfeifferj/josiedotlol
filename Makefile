IMAGE  ?= josie-lol
PORT   ?= 8080

.PHONY: build run serve stop clean generate lint hooks

build:
	podman build -t $(IMAGE) .

run:
	podman run --rm --name $(IMAGE) -p $(PORT):8080 $(IMAGE)

serve:
	$(MAKE) build
	$(MAKE) run

stop:
	-podman stop $(IMAGE)

clean: stop
	-podman rmi $(IMAGE)

generate:
	python3 scripts/build.py

lint:
	pre-commit run --all-files

hooks:
	pre-commit install
