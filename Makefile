up:
	docker-compose up

down:
	docker-compose down --volumes

start:
	docker-compose start

stop:
	docker-compose stop

agent:
	docker run --rm --network pupperware_default puppet/puppet-agent-alpine

clean:
	rm -rf ./volumes

.PHONY: up down start stop agent clean
