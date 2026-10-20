build:
	GOOS=darwin GOARCH=arm64 go build -v -tags with_gvisor .
	GOOS=ios GOARCH=arm64 go build -v -tags with_gvisor .
	GOOS=linux GOARCH=amd64 go build -v -tags with_gvisor .
	GOOS=linux GOARCH=arm64 go build -v -tags with_gvisor .
	GOOS=linux GOARCH=386 go build -v -tags with_gvisor .
	GOOS=linux GOARCH=arm go build -v -tags with_gvisor .
	GOOS=android GOARCH=arm64 go build -v -tags with_gvisor .
	GOOS=windows GOARCH=amd64 go build -v -tags with_gvisor .

fmt:
	@gofumpt -l -w .
	@gofmt -s -w .
	@gci write --custom-order -s standard -s "prefix(github.com/sagernet/)" -s "default" .

fmt_install:
	go install -v mvdan.cc/gofumpt@latest
	go install -v github.com/daixiang0/gci@latest

lint:
	GOOS=linux golangci-lint run .
	GOOS=android golangci-lint run .
	GOOS=windows golangci-lint run .
	GOOS=darwin golangci-lint run .
	GOOS=freebsd golangci-lint run .

lint_install:
	go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest

test:
	go build -v .
	#go test -v .
