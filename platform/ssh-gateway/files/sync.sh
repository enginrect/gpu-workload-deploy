#!/bin/sh
# telox-ssh-gateway 대역의 sync: 이 cluster의 Instance → sshpiper workingdir(/var/sshpiper/<instance>/). 실제 gateway는 API watch로 즉시 반영
#   authorized_keys  = Instance spec.authorizedKeys(고객 키, sshpiper가 검증)
#   sshpiper_upstream = 기본(exec):  <instance>@127.0.0.1:2022(exec-sshd → kubectl exec)
#                       full(sshd):  annotation telox.io/ssh-mode=sshd → <ssh-user>@<instance>.<ns>.svc.cluster.local:<ssh-port>(Instance sshd, 상행 키 = 플랫폼 키)
#   id_rsa           = 플랫폼 상행 키(Secret upstream_ed25519, 파일명은 sshpiper 고정)
set -u
apk add --no-cache kubectl jq >/dev/null 2>&1
ROOT=/var/sshpiper; IV=${SYNC_INTERVAL:-3}; mkdir -p $ROOT; chmod 711 $ROOT
TAB=$(printf '\t')
while :; do
  seen=""
  kubectl get instances.telox.io -A -o json 2>/dev/null | jq -r '.items[] | "\(.metadata.namespace)\t\(.metadata.name)\t\(.metadata.annotations["telox.io/ssh-mode"] // "exec")\t\(.metadata.annotations["telox.io/ssh-user"] // "root")\t\(.metadata.annotations["telox.io/ssh-port"] // "22")\t\((.spec.authorizedKeys // []) | join("\n") | @base64)"' 2>/dev/null \
  | while IFS="$TAB" read -r ns name mode user port keysb64; do
      d=$ROOT/$name; mkdir -p $d; chmod 700 $d
      printf '%s' "$keysb64" | base64 -d > $d/.ak.tmp; chmod 600 $d/.ak.tmp; mv $d/.ak.tmp $d/authorized_keys
      if [ "$mode" = sshd ]; then up="$user@$name.$ns.svc.cluster.local:$port"; else up="$name@127.0.0.1:2022"; fi
      printf '%s\n' "$up" > $d/.up.tmp; chmod 600 $d/.up.tmp; mv $d/.up.tmp $d/sshpiper_upstream
      [ -f $d/id_rsa ] || { cp /keys/upstream_ed25519 $d/.k.tmp; chmod 400 $d/.k.tmp; mv $d/.k.tmp $d/id_rsa; }
      printf '%s\n' "$name" >> $ROOT/.seen.tmp
    done
  if [ -f $ROOT/.seen.tmp ]; then
    for d in $ROOT/*/; do n=$(basename "$d"); grep -qx "$n" $ROOT/.seen.tmp || { rm -rf "$d"; echo "sync: removed $n"; }; done
    rm -f $ROOT/.seen.tmp
  fi
  sleep $IV
done
