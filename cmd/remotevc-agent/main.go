package main

import (
	"flag"
	"fmt"
	"net"
	"os"

	"remotevc-agent/internal/proto"
	"remotevc-agent/internal/session"
)

const version = "0.1.0"

func genToken() string {
	b := make([]byte, 16)
	_, _ = net.Interfaces() // just to use net package if needed, but not here
	// Use simpler random for token
	for i := range b {
		b[i] = "abcdefghijklmnopqrstuvwxyz0123456789"[ ( (int(os.Getpid()) + i) * 31 ) % 36]
	}
	return string(b)
}

func main() {
	var stdio bool
	var tcpAddr string
	var token string
	flag.BoolVar(&stdio, "stdio", false, "use framed JSON over stdin/stdout")
	flag.StringVar(&tcpAddr, "tcp", "", "listen on TCP address (e.g. :9999)")
	flag.StringVar(&token, "token", "", "auth token (auto-generated if empty)")
	flag.Parse()

	if !stdio && tcpAddr == "" {
		fmt.Fprintln(os.Stderr, "usage: remotevc-agent --stdio OR --tcp :9999")
		os.Exit(2)
	}

	if token == "" && tcpAddr != "" {
		token = "vibe-" + genToken()
		fmt.Fprintf(os.Stderr, "==========================================\n")
		fmt.Fprintf(os.Stderr, "AUTH TOKEN: %s\n", token)
		fmt.Fprintf(os.Stderr, "==========================================\n")
	}

	sess := session.New(token)

	if tcpAddr != "" {
		ln, err := net.Listen("tcp", tcpAddr)
		if err != nil {
			fmt.Fprintln(os.Stderr, "Listen failed:", err)
			os.Exit(1)
		}
		fmt.Fprintf(os.Stderr, "Agent listening on TCP %s\n", tcpAddr)
		for {
			conn, err := ln.Accept()
			if err != nil {
				continue
			}
			go func(c net.Conn) {
				defer c.Close()
				tr := proto.NewStdioTransportWithCloser(c, c, c)
				srv := proto.NewServer(tr, sess, version)
				_ = srv.Run()
			}(conn)
		}
	} else {
		transport := proto.NewStdioTransport(os.Stdin, os.Stdout)
		server := proto.NewServer(transport, sess, version)
		if err := server.Run(); err != nil {
			fmt.Fprintln(os.Stderr, err.Error())
			os.Exit(1)
		}
	}
}
