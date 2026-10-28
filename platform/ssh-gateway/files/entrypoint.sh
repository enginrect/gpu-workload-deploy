#!/bin/sh
# telox-ssh-gateway stand-in: OpenSSH sshd = SSH gateway, kubectl exec with SA telox-broker = broker
set -eu
apk add --no-cache openssh-server openssh-keygen kubectl >/dev/null
addgroup -g 2000 telox 2>/dev/null || true
adduser -D -H -s /sbin/nologin -G telox telox-keys 2>/dev/null || true   # runs AuthorizedKeysCommand; needs the broker token (group telox)
mkdir -p /etc/ssh/keys /run/telox /var/log/telox /opt/telox
chmod 1777 /var/log/telox
touch /var/log/telox/sessions.log; chmod 666 /var/log/telox/sessions.log
cp /opt/telox-src/keys.sh /opt/telox-src/exec-into.sh /opt/telox/
chmod 755 /opt/telox/keys.sh /opt/telox/exec-into.sh
[ -f /etc/ssh/keys/ssh_host_ed25519_key ] || ssh-keygen -q -t ed25519 -N '' -f /etc/ssh/keys/ssh_host_ed25519_key
echo "host key: $(ssh-keygen -lf /etc/ssh/keys/ssh_host_ed25519_key.pub)"
cat > /etc/ssh/sshd_config <<CFG
Port 22
AddressFamily inet
HostKey /etc/ssh/keys/ssh_host_ed25519_key
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
AuthorizedKeysFile none
AuthorizedKeysCommand /opt/telox/keys.sh %u
AuthorizedKeysCommandUser telox-keys
AllowTcpForwarding no
AllowAgentForwarding no
AllowStreamLocalForwarding no
X11Forwarding no
PermitTunnel no
PermitUserRC no
PermitUserEnvironment no
PrintMotd no
LogLevel VERBOSE
MaxAuthTries 3
ClientAliveInterval 60
ClientAliveCountMax 3
PidFile /run/sshd.pid
PerSourcePenaltyExemptList 127.0.0.0/8,10.17.0.0/16,10.18.0.0/16
CFG
cat > /run/telox/kubeconfig <<KC
apiVersion: v1
kind: Config
clusters:
- name: in
  cluster: {server: https://kubernetes.default.svc, certificate-authority: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt}
users:
- name: broker
  user: {tokenFile: /run/telox/token}
contexts:
- name: c
  context: {cluster: in, user: broker}
current-context: c
KC
chmod 644 /run/telox/kubeconfig
sync_loop() {
  while :; do
    cp /var/run/secrets/kubernetes.io/serviceaccount/token /run/telox/token.tmp && chgrp telox /run/telox/token.tmp && chmod 640 /run/telox/token.tmp && mv /run/telox/token.tmp /run/telox/token
    kubectl get instances.telox.io -A -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | while read -r i; do
      [ -n "$i" ] || continue
      id "$i" >/dev/null 2>&1 && continue
      if adduser -D -H -s /bin/sh -G telox "$i" 2>/dev/null; then
        sed -i "s|^$i:![^:]*:|$i:*:|" /etc/shadow
        echo "user-sync: created login $i"
      fi
    done
    sleep 15
  done
}
sync_loop &
exec /usr/sbin/sshd -D -e -f /etc/ssh/sshd_config
