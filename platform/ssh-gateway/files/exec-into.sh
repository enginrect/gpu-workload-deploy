#!/bin/sh
# forced command: resolve Instance -> namespace/pod in this cluster, then pods/exec as SA telox-broker
export KUBECONFIG=/run/telox/kubeconfig
inst="$(id -un)"
ns="$(kubectl get instances.telox.io -A --field-selector "metadata.name=$inst" -o jsonpath='{.items[0].metadata.namespace}' 2>/dev/null || true)"
if [ -z "$ns" ]; then echo "telox: instance $inst is not in this cluster" >&2; exit 1; fi
pod="$(kubectl get instances.telox.io -n "$ns" "$inst" -o jsonpath='{.status.podName}' 2>/dev/null || true)"; pod="${pod:-$inst}"
printf '%s inst=%s ns=%s pod=%s client=%s cmd=%s\n' "$(date -u +%FT%TZ)" "$inst" "$ns" "$pod" "${SSH_CLIENT%% *}" "${SSH_ORIGINAL_COMMAND:-<shell>}" >> /var/log/telox/sessions.log 2>/dev/null || true
t=""; [ -t 0 ] && t="-t"
if [ -n "${SSH_ORIGINAL_COMMAND:-}" ]; then
  exec kubectl exec -i $t -n "$ns" "$pod" -c main -- sh -c "$SSH_ORIGINAL_COMMAND"
fi
exec kubectl exec -i $t -n "$ns" "$pod" -c main -- sh -c 'command -v bash >/dev/null 2>&1 && exec bash -l || exec sh -l'
