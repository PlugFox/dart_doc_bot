.PHONY: build run push deploy shell

build:
	@docker build -t plugfox/dart-doc-bot:latest .

run:
	@docker run -it -d --rm -p 8080:8080 --name dart-doc-bot plugfox/dart-doc-bot:latest

push: deploy

deploy:
	@docker push plugfox/dart-doc-bot:latest

shell:
	@docker run -it --rm --name dart-doc-bot plugfox/dart-doc-bot:latest /bin/bash