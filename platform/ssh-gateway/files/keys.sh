#!/bin/sh
# exec-sshd AuthorizedKeysCommand(상행): sshpiper가 플랫폼 키로 들어옴. 로그인 이름 = Instance id가 이 cluster에 있으면 플랫폼 공개키(강제 명령 exec-into.sh)를 허용. 고객 키 검증은 sshpiper(sync.sh의 authorized_keys)
export KUBECONFIG=/run/telox/kubeconfig HOME=/tmp
n="$(kubectl get instances.telox.io -A --field-selector "metadata.name=$1" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
[ "$n" = "$1" ] || exit 0
printf 'restrict,pty,command="/opt/telox/exec-into.sh" %s\n' "$(cat /opt/telox/upstream.pub)"
