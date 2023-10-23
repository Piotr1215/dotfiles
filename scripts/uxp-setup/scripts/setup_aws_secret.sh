#!/usr/bin/env bash

set -eo pipefail

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: aws-creds
  namespace: $xp_namespace
stringData:
  creds: |
    $(printf "[default]\n    aws_access_key_id = %s\n    aws_secret_access_key = %s" "${AWS_KEY_ID}" "${AWS_SECRET}")
EOF
