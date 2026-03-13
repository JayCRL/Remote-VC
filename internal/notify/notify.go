package notify

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"time"
)

func Send(title, message string) {
	url := os.Getenv("REMOTEVC_NOTIFY_URL")
	if url == "" {
		return
	}

	go func() {
		payload := map[string]string{
			"title":   title,
			"message": message,
		}
		b, _ := json.Marshal(payload)
		
		client := &http.Client{Timeout: 5 * time.Second}
		resp, err := client.Post(url, "application/json", bytes.NewBuffer(b))
		if err != nil {
			fmt.Fprintf(os.Stderr, "Notification failed: %v\n", err)
			return
		}
		defer resp.Body.Close()
	}()
}
