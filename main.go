package main

import (
	"encoding/xml"
	"fmt"
	"io"
	"net/http"
	"strings"
)

// デバイス記述XMLの構造
type DeviceDescription struct {
	XMLName xml.Name `xml:"root"`
	Device  Device   `xml:"device"`
}

type Device struct {
	DeviceType   string        `xml:"deviceType"`
	FriendlyName string        `xml:"friendlyName"`
	Manufacturer string        `xml:"manufacturer"`
	ModelName    string        `xml:"modelName"`
	ServiceList  []Service     `xml:"serviceList>service"`
}

type Service struct {
	ServiceType string `xml:"serviceType"`
	ServiceId   string `xml:"serviceId"`
	ControlURL  string `xml:"controlURL"`
	EventSubURL string `xml:"eventSubURL"`
	SCPDURL     string `xml:"SCPDURL"`
}

// DIDL-Lite (コンテンツディレクトリ応答) の構造
type DIDLLite struct {
	XMLName    xml.Name    `xml:"DIDL-Lite"`
	Containers []Container `xml:"container"`
	Items      []Item      `xml:"item"`
}

type Container struct {
	ID         string `xml:"id,attr"`
	ParentID   string `xml:"parentID,attr"`
	Title      string `xml:"title"`
	Class      string `xml:"class"`
	ChildCount int    `xml:"childCount,attr"`
}

type Item struct {
	ID       string   `xml:"id,attr"`
	ParentID string   `xml:"parentID,attr"`
	Title    string   `xml:"title"`
	Class    string   `xml:"class"`
	Date     string   `xml:"date"`
	Res      []Resource `xml:"res"`
}

type Resource struct {
	URL          string `xml:",chardata"`
	ProtocolInfo string `xml:"protocolInfo,attr"`
	Size         string `xml:"size,attr"`
	Resolution   string `xml:"resolution,attr"`
}

func getDeviceDescription(url string) (*DeviceDescription, error) {
	resp, err := http.Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	var desc DeviceDescription
	err = xml.Unmarshal(body, &desc)
	if err != nil {
		return nil, err
	}

	return &desc, nil
}

func browseContentDirectory(baseURL, controlURL, objectID string) (*DIDLLite, error) {
	soapAction := "urn:schemas-upnp-org:service:ContentDirectory:1#Browse"
	
	soapBody := fmt.Sprintf(`<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:Browse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">
      <ObjectID>%s</ObjectID>
      <BrowseFlag>BrowseDirectChildren</BrowseFlag>
      <Filter>*</Filter>
      <StartingIndex>0</StartingIndex>
      <RequestedCount>100</RequestedCount>
      <SortCriteria></SortCriteria>
    </u:Browse>
  </s:Body>
</s:Envelope>`, objectID)

	// controlURLが相対パスの場合、絶対URLに変換
	fullURL := controlURL
	if !strings.HasPrefix(controlURL, "http") {
		fullURL = baseURL + controlURL
	}

	req, err := http.NewRequest("POST", fullURL, strings.NewReader(soapBody))
	if err != nil {
		return nil, err
	}

	req.Header.Set("Content-Type", "text/xml; charset=utf-8")
	req.Header.Set("SOAPAction", fmt.Sprintf(`"%s"`, soapAction))

	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	// SOAP応答からDIDL-Liteを抽出
	bodyStr := string(body)
	
	// ResultタグからDIDL-Liteを抽出
	startTag := "<Result>"
	endTag := "</Result>"
	startIdx := strings.Index(bodyStr, startTag)
	endIdx := strings.Index(bodyStr, endTag)
	
	if startIdx == -1 || endIdx == -1 {
		return nil, fmt.Errorf("DIDL-Lite not found in response")
	}

	didlStr := bodyStr[startIdx+len(startTag) : endIdx]
	// XMLエスケープを解除
	didlStr = strings.ReplaceAll(didlStr, "&lt;", "<")
	didlStr = strings.ReplaceAll(didlStr, "&gt;", ">")
	didlStr = strings.ReplaceAll(didlStr, "&quot;", "\"")
	didlStr = strings.ReplaceAll(didlStr, "&amp;", "&")

	var didl DIDLLite
	err = xml.Unmarshal([]byte(didlStr), &didl)
	if err != nil {
		return nil, fmt.Errorf("XML parse error: %v\nDIDL: %s", err, didlStr)
	}

	return &didl, nil
}

func listImagesRecursive(baseURL, controlURL, objectID string, indent string) error {
	didl, err := browseContentDirectory(baseURL, controlURL, objectID)
	if err != nil {
		return err
	}

	// コンテナ（フォルダ）を表示
	for _, container := range didl.Containers {
		fmt.Printf("%s📁 %s (ID: %s, 子要素: %d個)\n", 
			indent, container.Title, container.ID, container.ChildCount)
		
		// 再帰的に子要素を取得
		if container.ChildCount > 0 {
			listImagesRecursive(baseURL, controlURL, container.ID, indent+"  ")
		}
	}

	// アイテム（画像）を表示
	for _, item := range didl.Items {
		if strings.Contains(item.Class, "image") {
			fmt.Printf("%s🖼️  %s\n", indent, item.Title)
			if item.Date != "" {
				fmt.Printf("%s   日付: %s\n", indent, item.Date)
			}
			for _, res := range item.Res {
				if res.Resolution != "" {
					fmt.Printf("%s   解像度: %s\n", indent, res.Resolution)
				}
				if res.Size != "" {
					fmt.Printf("%s   サイズ: %s bytes\n", indent, res.Size)
				}
				fmt.Printf("%s   URL: %s\n", indent, res.URL)
			}
			fmt.Println()
		}
	}

	return nil
}

func main() {
	deviceURL := "http://10.0.0.1:64321/DmsDesc.xml"
	
	fmt.Println("=== デバイス情報取得中 ===\n")
	
	desc, err := getDeviceDescription(deviceURL)
	if err != nil {
		fmt.Printf("エラー: %v\n", err)
		return
	}

	fmt.Printf("デバイス名: %s\n", desc.Device.FriendlyName)
	fmt.Printf("製造元: %s\n", desc.Device.Manufacturer)
	fmt.Printf("モデル: %s\n", desc.Device.ModelName)
	fmt.Println()

	// ContentDirectoryサービスを探す
	var controlURL string
	for _, service := range desc.Device.ServiceList {
		if strings.Contains(service.ServiceType, "ContentDirectory") {
			controlURL = service.ControlURL
			fmt.Printf("ContentDirectory サービス検出: %s\n", service.ServiceType)
			fmt.Printf("Control URL: %s\n", controlURL)
			break
		}
	}

	if controlURL == "" {
		fmt.Println("ContentDirectoryサービスが見つかりません")
		return
	}

	fmt.Println("\n=== 画像リスト取得中 ===\n")
	
	// ベースURL (http://10.0.0.1:64321)
	baseURL := "http://10.0.0.1:64321"
	
	// ルートからブラウズ開始
	err = listImagesRecursive(baseURL, controlURL, "0", "")
	if err != nil {
		fmt.Printf("エラー: %v\n", err)
		return
	}

	fmt.Println("\n✓ 完了")
}
