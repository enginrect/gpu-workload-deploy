# Karmada를 Argo CD 대상 클러스터로 쓰는 실측 (branch karmada-argocd-test)

hub Argo CD(tech-neo-mgmt)에 karmada-apiserver(10.7.56.32:5443)를 cluster `tech-neo-karmada`로 등록하고,
neocloud CR(SKU · Domain · Instance)을 Git → Argo CD → karmada-apiserver → PropagationPolicy → tech-neo-wkld 경로로 배포해 동작을 확인하는 브랜치.
플랫폼(gpu-operator · Kyverno · DRA 등)은 main 브랜치의 직접 배포 경로 그대로이고, 이 브랜치는 CR 경로만 다룸.

- `bootstrap/appproject.yaml` — AppProject karmada-test (cluster Secret은 인증서가 들어가므로 리포에 두지 않음)
- `root.yaml` → `apps/` — app-of-apps. wave 0 crds(karmada-apiserver에 neocloud CRD) → 1 sku → 2 domain-c → 3 instances
- `sku/` `domain-c/` `instances/` — CR + (Cluster)PropagationPolicy
- `tests/` — 개별 확인용(namespace 자동 전파 · hook Job · webhook 전파 · CRD+CR 동시 · interpreter)
