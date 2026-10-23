# karmada/bootstrap — hub 쪽 1회 적용 (Karmada 경로의 플랫폼 전제)

hub(tech-neo-mgmt) argocd ns에 손으로 apply — `KUBECONFIG=~/.kube/tech-neo-mgmt.config kubectl apply -f karmada/bootstrap/`.
Karmada Controlplane 설치(helm, karmada-tech-test/values-mgmt.yaml) · cluster 등록(Secret, 리포 밖)과 같은 층. `karmada/root.yaml`(telox app root)과 분리돼 있어 root 커밋과 같은 sync에 섞이지 않음 — CRD 변경은 여기서 먼저, CR은 root에서 나중에.

- `appproject.yaml` — AppProject karmada-test
- `apiserver-crds-gateway.yaml` — gateway-crds-helm v1.9.2(직접 경로와 같은 chart · 같은 values)를 karmada-apiserver에 설치: Gateway API v1.6.1 standard CRD + safe-upgrades VAP + Envoy Gateway CRD. template 저장용(멤버 전파 없음)
- `apiserver-crds-kyverno.yaml` → `crds/kyverno/` — Kyverno chart 3.7.1 렌더의 ClusterPolicy · ValidatingPolicy CRD 그대로(chart가 CRD만 설치하는 값이 없어 복사). 같은 용도
- telox 자신의 CRD(telox.io)는 상품과 같이 바뀌므로 여기가 아니라 root wave 0(`karmada/telox-crds`, 멤버 전파 CPP 포함)
