.PHONY: fmt lint check clean

fmt:
	stylua lua/

lint:
	selene lua/

check: fmt lint

clean:
	rm -rf .luacheckcache
