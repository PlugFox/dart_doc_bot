.PHONY: build run push deploy shell

build:
	@docker build -t plugfox/dart-doc-bot:0.0.1 .

run:
	@docker run -it -d --rm -p 8080:8080 --name dart-doc-bot plugfox/dart-doc-bot:0.0.1

push: deploy

deploy:
	@docker push plugfox/dart-doc-bot:0.0.1

shell:
	@docker run -it --rm --name dart-doc-bot plugfox/dart-doc-bot:0.0.1 /bin/bash