# Karmada를 Argo CD 대상 클러스터로 쓰는 실측 (branch karmada-argocd-test)

hub Argo CD(tech-neo-mgmt)에 karmada-apiserver(10.7.56.32:5443)를 cluster `tech-neo-karmada`로 등록하고,
neocloud CR(SKU · Domain · Instance)을 Git → Argo CD → karmada-apiserver → PropagationPolicy → tech-neo-wkld 경로로 배포해 동작을 확인하는 브랜치.
플랫폼(gpu-operator · Kyverno · DRA 등)은 main 브랜치의 직접 배포 경로 그대로이고, 이 브랜치는 CR 경로만 다룸.

- `bootstrap/appproject.yaml` — AppProject karmada-test (cluster Secret은 인증서가 들어가므로 리포에 두지 않음)
- `root.yaml` → `apps/` — app-of-apps. wave 0 crds(karmada-apiserver에 neocloud CRD) → 1 sku → 2 domain-c → 3 instances
- `sku/` `domain-c/` `instances/` — CR + (Cluster)PropagationPolicy
- `tests/` — 개별 확인용(namespace 자동 전파 · hook Job · webhook 전파 · CRD+CR 동시 · interpreter)

## 결과 (실측, tech)

- 등록 · 전파 — cluster 등록 Successful(API 77), root 생성 13초 안에 4 App Synced · 멤버에 ns · Domain · SKU · Instance 생성
- 리소스 트리 — ResourceBinding · ClusterResourceBinding이 template 자식으로 표시(Argo 내장 health). 멤버 Pod는 안 보임
- 멤버 Kyverno 거부(k2) — Work · ResourceBinding에는 거부 메시지, 트리는 Degraded, **App은 Synced · Healthy 유지**(App health는 managed resource만 집계)
- health — neocloud CR은 Argo 내장 health가 없어 status 비어도 Healthy. `tests/interpreter`(statusAggregation · healthInterpretation) + hub Lua health(Domain Ready / Instance phase) 뒤 Domain c · Instance k1 Healthy(멤버 메시지), status 없는 k2 Progressing. 기존 binding은 RIC 적용 뒤 template을 건드려야 집계 시작
- SSA diff — 리스트 안 기본값(`ports[].protocol` CRD default, PP `resourceSelectors[].namespace` webhook default)은 ServerSideDiff로도 OutOfSync → Git에 명시(`instances/k1.yaml` 주석)
- drift — template patch는 0.2초 뒤 멤버에 먼저 반영되고 0.8초 뒤 Argo selfHeal이 되돌림. OverridePolicy는 멤버만 바꾸고 Argo Synced 유지
- namespace — CreateNamespace=true가 만든 namespace는 skip label이 없어 멤버에 자동 전파되고 App 삭제 뒤에도 남음(`managedNamespaceMetadata`로 label은 가능) → namespace는 매니페스트로
- hook Job — PP 없으면 "waiting for completion of hook"에서 정지, PP를 PreSync wave -1 hook으로 같이 두면 멤버 실행 · 집계로 12초 완료(`tests/hook-b`)
- webhook — `clientConfig.service` webhook은 karmada-apiserver에서 dial 실패(Fail = 거부, Ignore = timeout 지연). 전파된 webhook의 멤버 caBundle 주입은 1초 안에 되돌려지고 retention RIC(`tests/webhook-f2-retain`)로 유지
- CRD + CR 한 App — 한 sync에 적용 · 전파. App 삭제(cascade)는 CRD를 지우지 않음
- 남은 것 — `root.yaml` 4 App + `tests/apps/interpreter.yaml`. 나머지 tests App은 삭제함
