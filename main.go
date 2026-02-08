package main

import (
	"fmt"
	"net"
	"time"
)

const (
	ssdpAddr     = "239.255.255.250:1900"
	ssdpSearchST = "urn:schemas-sony-com:service:ScalarWebAPI:1"
)

func main() {
	// M-SEARCHリクエストの作成
	searchRequest := fmt.Sprintf(
		"M-SEARCH * HTTP/1.1\r\n"+
			"HOST: %s\r\n"+
			"MAN: \"ssdp:discover\"\r\n"+
			"MX: 1\r\n"+
			"ST: %s\r\n"+
			"USER-AGENT: Go/1.0 SSDP-Discovery/1.0\r\n"+
			"\r\n",
		ssdpAddr,
		ssdpSearchST,
	)

	// UDPアドレスの解決
	addr, err := net.ResolveUDPAddr("udp4", ssdpAddr)
	if err != nil {
		fmt.Printf("アドレス解決エラー: %v\n", err)
		return
	}

	// UDP接続の作成
	conn, err := net.ListenUDP("udp4", nil)
	if err != nil {
		fmt.Printf("UDP接続エラー: %v\n", err)
		return
	}
	defer conn.Close()

	// タイムアウトの設定
	conn.SetReadDeadline(time.Now().Add(3 * time.Second))

	// M-SEARCHリクエストの送信
	_, err = conn.WriteToUDP([]byte(searchRequest), addr)
	if err != nil {
		fmt.Printf("送信エラー: %v\n", err)
		return
	}

	fmt.Println("M-SEARCHリクエストを送信しました")
	fmt.Println("応答を待機中...")
	fmt.Println()

	// 応答の受信
	buffer := make([]byte, 8192)
	for {
		n, remoteAddr, err := conn.ReadFromUDP(buffer)
		if err != nil {
			if netErr, ok := err.(net.Error); ok && netErr.Timeout() {
				fmt.Println("タイムアウト: 応答がありませんでした")
				break
			}
			fmt.Printf("受信エラー: %v\n", err)
			break
		}

		fmt.Printf("=== 応答元: %s ===\n", remoteAddr)
		fmt.Println(string(buffer[:n]))
		fmt.Println()
	}
}
