miuimon: main.go
	go get -d -v ./...
	go build -o $@ -v -ldflags "-s -w" main.go

clean:
	rm -f miuimon

.PHONY: clean