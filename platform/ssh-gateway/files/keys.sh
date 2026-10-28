#!/bin/sh
# AuthorizedKeysCommand: login name = Instance id; keys = Instance spec.authorizedKeys in THIS cluster (API read at every login, no cache → revoke is immediate after propagation)
export KUBECONFIG=/run/telox/kubeconfig HOME=/tmp
kubectl get instances.telox.io -A --field-selector "metadata.name=$1" -o jsonpath='{range .items[0].spec.authorizedKeys[*]}{@}{"\n"}{end}' 2>/dev/null \
  | grep -v '^[[:space:]]*$' | sed 's|^|restrict,pty,command="/opt/telox/exec-into.sh" |'
