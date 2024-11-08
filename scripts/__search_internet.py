#!/usr/bin/env python3
import os
import argparse
import requests

def main():
    parser = argparse.ArgumentParser(description="Query the Perplexity AI API.")
    parser.add_argument("query", type=str, help="The query to send to the API.")
    args = parser.parse_args()

    url = "https://api.perplexity.ai/chat/completions"

    payload = {
        "model": "llama-3.1-sonar-large-128k-online",
        "messages": [
            {
                "role": "system",
                "content": "Be precise and concise and return citations and sources."
            },
            {"role": "user", "content": args.query}
        ],
        "temperature": 0.2,
        "top_p": 0.9,
        "search_domain_filter": ["perplexity.ai"],
        "return_images": False,
        "return_related_questions": False,
        "search_recency_filter": "month",
        "top_k": 0,
        "stream": False,
        "presence_penalty": 0,
        "frequency_penalty": 1
    }
    headers = {
        "Authorization": f"Bearer {os.getenv('PPLX_API_KEY')}",
        "Content-Type": "application/json"
    }

    response = requests.request("POST", url, json=payload, headers=headers)
    response_data = response.json()
    message_content = response_data.get("choices", [])[0].get("message", {}).get("content", "")
    print(message_content)

if __name__ == "__main__":
    main()
