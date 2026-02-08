package main

import (
	"fmt"
	"net"
	"strings"
	"time"
)

func searchSSDP(searchTarget string, mx int, timeout time.Duration) {
	ssdpAddr := "239.255.255.250:1900"

	searchRequest := fmt.Sprintf(
		"M-SEARCH * HTTP/1.1\r\n"+
			"HOST: %s\r\n"+
			"MAN: \"ssdp:discover\"\r\n"+
			"MX: %d\r\n"+
			"ST: %s\r\n"+
			"USER-AGENT: Go/1.0 SSDP-Discovery/1.0\r\n"+
			"\r\n",
		ssdpAddr,
		mx,
		searchTarget,
	)

	fmt.Printf("検索対象: %s\n", searchTarget)
	fmt.Printf("最大待機時間: %v\n", timeout)
	fmt.Println(strings.Repeat("-", 60))

	addr, err := net.ResolveUDPAddr("udp4", ssdpAddr)
	if err != nil {
		fmt.Printf("アドレス解決エラー: %v\n", err)
		return
	}

	// UDPソケットを作成（特定のインターフェースにバインド）
	conn, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4zero, Port: 0})
	if err != nil {
		fmt.Printf("UDP接続エラー: %v\n", err)
		return
	}
	defer conn.Close()

	// タイムアウトの設定
	conn.SetReadDeadline(time.Now().Add(timeout))

	// リクエスト送信
	n, err := conn.WriteToUDP([]byte(searchRequest), addr)
	if err != nil {
		fmt.Printf("送信エラー: %v\n", err)
		return
	}

	fmt.Printf("✓ %d バイト送信完了\n", n)
	fmt.Println("応答を待機中...\n")

	// 応答受信
	buffer := make([]byte, 8192)
	deviceCount := 0

	for {
		n, remoteAddr, err := conn.ReadFromUDP(buffer)
		if err != nil {
			if netErr, ok := err.(net.Error); ok && netErr.Timeout() {
				if deviceCount == 0 {
					fmt.Println("⚠ タイムアウト: 応答がありませんでした")
				} else {
					fmt.Printf("\n✓ 合計 %d 個のデバイスから応答を受信\n", deviceCount)
				}
				break
			}
			fmt.Printf("受信エラー: %v\n", err)
			break
		}

		deviceCount++
		response := string(buffer[:n])

		fmt.Printf("【デバイス %d】 from %s\n", deviceCount, remoteAddr)
		fmt.Println(strings.Repeat("=", 60))
		fmt.Println(response)
		fmt.Println()
	}
}

func main() {
	// まず全デバイスを検索
	fmt.Println("=== すべてのUPnPデバイスを検索 ===\n")
	searchSSDP("ssdp:all", 3, 5*time.Second)

	fmt.Println("\n" + strings.Repeat("=", 60))
	fmt.Println()

	// 次にSony ScalarWebAPIを検索
	fmt.Println("=== Sony ScalarWebAPI デバイスを検索 ===\n")
	searchSSDP("urn:schemas-sony-com:service:ScalarWebAPI:1", 3, 5*time.Second)
}
