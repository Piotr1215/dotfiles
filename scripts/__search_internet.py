#!/usr/bin/env python3
import os
import argparse
import requests

def main():
    parser = argparse.ArgumentParser(description="Query the Perplexity AI API.")
    parser.add_argument("query", type=str, help="The query to send to the API.")
    parser.add_argument("--pro", action="store_true", help="Use the sonar-pro model instead of sonar")
    args = parser.parse_args()
    
    model = "sonar-pro" if args.pro else "sonar"
    url = "https://api.perplexity.ai/chat/completions"
    
    payload = {
        "model": model,
        "messages": [
            {
                "role": "system",
                "content": "Be precise and concise."
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
    
    # Extract message content and citations
    message = response_data["choices"][0]["message"]["content"]
    citations = response_data["citations"]
    
    # Create references section
    references = "\n\n## References\n\n"
    for i, url in enumerate(citations, 1):
        references += f"[{i}]: {url}\n"
    
    # Combine and print
    print(f"{message}{references}")

if __name__ == "__main__":
    main()
