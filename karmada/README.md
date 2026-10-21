# Karmada 경로 (branch karmada-argocd-test)

multi-region · multi-cluster 구조에서 telox 몫(CRD · ns telox-system · SA · RBAC · Kyverno 정책 · SKU · Domain · Instance)을
Git → Argo CD → karmada-apiserver(cluster `tech-neo-karmada`) → (Cluster)PropagationPolicy → wkld 멤버 경로로 배포하는 디렉터리.
플랫폼(gpu-operator · Kyverno chart · DRA · nri · Envoy Gateway · ExternalDNS · Cilium 정책 · 플랫폼 RBAC)은 `apps/` + `platform/`의 직접 배포 경로(클러스터마다 Application).

## 구조

- `bootstrap/appproject.yaml` — AppProject karmada-test (cluster Secret은 인증서가 들어가므로 리포 밖)
- `root.yaml` → `apps/` — app-of-apps
  - wave 0 `telox-crds/`(CRD 4종 + CPP) · `kyverno-crds/`(ClusterPolicy · ValidatingPolicy CRD, karmada-apiserver 저장용) · `interpreter/`(RIC 5종)
  - wave 1 `system-rbac/`(ns telox-system + SA + ClusterRole/Binding + Kyverno aggregated ClusterRole + CPP)
  - wave 2 `kyverno-policies/`(telox 정책 8 + CPP)
  - wave 3 `sku/` → 4 `domain-c/` → 5 `instances/`
- 전파 범위
  - 모든 wkld 멤버(`clusterAffinity.labelSelector telox.io/role=wkld`) — CRD · RBAC · 정책 · SKU
  - 클러스터 하나(`clusterNames`) — Domain + domain namespace, Instance(domain namespace의 PropagationPolicy)
  - 멤버 Cluster 오브젝트에 `spec.region` · `spec.provider` · `spec.zones` + label `telox.io/role` · `telox.io/region`
- `tests/` — 개별 확인용(namespace 자동 전파 · hook Job · webhook 전파 · CRD+CR 동시)

## 결과 (실측, tech · 멤버 1개)

- 등록 · 전파 — cluster 등록 Successful(API 77), root 생성 13초 안에 App Synced · 멤버에 ns · Domain · SKU · Instance 생성
- 직접 경로 → Karmada 경로 이동 — 직접 Application 3개(finalizer 없음)를 지우고 root를 이 브랜치로 바꾼 뒤 CPP `conflictResolution: Overwrite`로 채택. CRD 2초 · RBAC 8초 · 정책 23초 안에 FullyApplied, 멤버 오브젝트 23개 uid 전부 유지, Kyverno 재시작 0, 거부 동작 유지(allowedSkus 밖 sku Instance는 Work Applied False)
- health — RIC statusAggregation(ClusterPolicy `conditions[Ready]` · ValidatingPolicy `conditionStatus.ready`, 멤버 전부 AND) + hub Lua(`kyverno.io_ClusterPolicy` · `policies.kyverno.io_ValidatingPolicy` · `telox.io_ServerlessInstance`)로 정책 App Synced · Healthy. Karmada 내장 kyverno.io 해석은 `status.ready` 필드만 집계해 Kyverno 1.17(conditions만 기록)에서는 template status가 비어 있음 → RIC 필수
- 순서 — 멤버에 CRD가 없는 kind는 scheduler가 `NoClusterFit`(apiEnablements)으로 보류, CRD 전파 뒤 재시도로 배치(약 2분). Kyverno chart보다 정책을 먼저 적용해도 됨
- 리소스 트리 — ResourceBinding · ClusterResourceBinding이 template 자식으로 표시(Argo 내장 health). 멤버 Pod는 안 보임
- 멤버 Kyverno 거부 — Work · ResourceBinding에는 거부 메시지, 트리는 Degraded, **App은 Synced · Healthy 유지**(App health는 managed resource만 집계)
- telox CR health — RIC(Domain Ready · Instance phase) + hub Lua로 Domain c · Instance k1 Healthy(멤버 메시지), status 없는 CR은 Progressing. 기존 binding은 RIC 적용 뒤 template을 건드려야 집계 시작
- SSA diff — 리스트 안 기본값(`ports[].protocol` CRD default, PP `resourceSelectors[].namespace` webhook default)은 ServerSideDiff로도 OutOfSync → Git에 명시(`instances/k1.yaml` 주석)
- drift — template patch는 0.2초 뒤 멤버에 먼저 반영되고 0.8초 뒤 Argo selfHeal이 되돌림. OverridePolicy는 멤버만 바꾸고 Argo Synced 유지
- namespace — CreateNamespace=true가 만든 namespace는 skip label이 없어 멤버에 자동 전파되고 App 삭제 뒤에도 남음 → namespace는 매니페스트로(skip label + CPP 선택)
- hook Job — PP 없으면 "waiting for completion of hook"에서 정지, PP를 PreSync wave -1 hook으로 같이 두면 멤버 실행 · 집계로 12초 완료(`tests/hook-b`)
- webhook — `clientConfig.service` webhook은 karmada-apiserver에서 dial 실패(Fail = 거부, Ignore = timeout 지연). 전파된 webhook의 멤버 caBundle 주입은 1초 안에 되돌려지고 retention RIC(`tests/webhook-f2-retain`)로 유지 → webhook이 있는 플랫폼은 직접 경로
- CRD — App 삭제(cascade)는 CRD를 지우지 않음. CPP `preserveResourcesOnDeletion: true`로 template 삭제 때도 멤버 CRD 유지

## main 머지 때

- `apps/platform-rbac.yaml` targetRevision → main
- `bootstrap/appproject.yaml`에 destination `tech-neo-karmada` 추가, `karmada/bootstrap/appproject.yaml`(karmada-test) 폐기
- hub `telox-platform-root` targetRevision → main
