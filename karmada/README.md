# Karmada 경로 (branch karmada-argocd-test)

multi-region · multi-cluster 구조에서 telox 몫 가운데 컨트롤러 · webhook이 없고 agent에 cluster-admin급 권한을 요구하지 않는 것(SKU · Domain + domain namespace · Domain 전개 오브젝트 · Instance · 노출 · project Gateway)을
Git → Argo CD → karmada-apiserver(cluster `tech-neo-karmada`) → (Cluster)PropagationPolicy → wkld 멤버 경로로 배포하는 디렉터리.
플랫폼(gpu-operator · Kyverno chart · DRA · nri · Envoy Gateway · ExternalDNS · Cilium 정책 · 플랫폼 RBAC)과 **telox CRD · ns telox-system · SA · ClusterRole/Binding · Kyverno 정책 · SSH gateway**는 `apps/` + `platform/`의 직접 배포 경로(클러스터마다 Application) — CRD · ClusterRole · 정책 · Deployment는 agent에 escalate · bind · cluster-admin급 권한을 요구하므로 Karmada 경로에서 뺌(직접 경로 이행, install.md §19).

## 구조

- `bootstrap/` — hub 쪽 1회 적용(손으로 apply): AppProject karmada-test + karmada-apiserver용 CRD 묶음(Gateway API chart 재사용 · Kyverno 렌더 그대로). Karmada 설치와 같은 층, root 밖 → CRD 변경은 CR 커밋보다 먼저. cluster Secret은 인증서가 들어가므로 리포 밖
- `root.yaml` → `apps/` — app-of-apps
  - wave 0 `crds.yaml` → `platform/telox-crds/`(telox CRD 4종을 karmada-apiserver에 저장만 — template 수신용. 멤버 CRD는 직접 경로의 같은 파일) · `interpreter/`(RIC 9종)
  - (이행됨) ns telox-system · SA · ClusterRole/Binding · Kyverno 정책 · SSH gateway → `platform/telox-rbac/` · `platform/kyverno-policies/` · `platform/ssh-gateway/`(직접 경로)
  - wave 3 `sku/` → 4 `domain-c/`(ns · Domain · CPP + `gateway-<project>.yaml` = project별 EnvoyProxy ep-dev · Gateway gw-dev · PP) → 5 `instances/`(Instance + Service · NetworkPolicy · HTTPRoute · ListenerSet · TCPRoute, PP 하나)
- 전파 범위
  - 모든 wkld 멤버(`clusterAffinity.labelSelector telox.io/role=wkld`) — SKU
  - domain이 걸치는 클러스터들(`clusterNames`, 클러스터별 값은 ClusterOverridePolicy) — Domain + domain namespace. Instance는 라벨 `telox.io/region`의 PropagationPolicy(labelSelector + region fieldSelector)가 그 리전의 클러스터 하나로(`instances-d/pp-regions.yaml`)
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

## project별 Gateway · Instance 노출 (실측, tech)

- 구조 — domain = namespace + lbPool, project = Gateway 1개(LB IP 1개 · ListenerSet 포트 공간 1개). domain namespace에 project마다 EnvoyProxy(ep-dev: Service label `telox.io/domain=c` · `telox.io/project=dev` · `lbipam.cilium.io/ips` = Domain lbPool 안 IP · eTP Local) + Gateway(gw-dev: GatewayClass telox, http 80 · https 443 `*.r1.neo.test`, allowedListeners Same, label dns-source) 1쌍을 Instance가 배치되는 리전의 클러스터로 PP 전파(domain이 여러 리전에 걸치면 리전마다 1쌍). 다른 project의 Envoy는 NetworkPolicy(owning-gateway label)로 Instance에 닿지 못함. Instance마다 ClusterIP Service(이름 = Instance) · gateway Envoy pod만 허용하는 NetworkPolicy · HTTPRoute(호스트명 `<name>-<port>-<project>-<domain>.r1.neo.test`) 또는 ListenerSet(TCP 포트) + TCPRoute를 같은 PP로 전파. TLS Secret은 리포 밖(멤버 domain ns에 직접, 운영은 cert-manager)
- 전파 — PP 적용 1초 안에 멤버 생성, Envoy pod Running · Gateway Accepted 즉시, Programmed +11초(주소 10.7.56.90, pool domain-c 1 used), Service 포트 80 · 443 · 10022. ExternalDNS가 HTTPRoute 호스트명 A 레코드를 6초 뒤 생성
- 접근(Mac) — HTTP 200 · HTTPS 200(인증서 CN `*.r1.neo.test`) · 미등록 호스트 404 · SSH 10022 → sshd 2222 응답(Permission denied = 경로 성립). backend가 보는 peer = Envoy pod IP, `X-Forwarded-For` = Mac IP
- health — RIC(Gateway Programmed · HTTPRoute/TCPRoute parents Accepted+ResolvedRefs · ListenerSet Programmed) + Argo 내장(Gateway · HTTPRoute) + hub Lua(ListenerSet · TCPRoute)로 App Synced · Healthy, 메시지 "Gateway is healthy" 등
- drift — 멤버 HTTPRoute 삭제 → 0.6초 재생성 · 1.2초 Accepted · HTTP 200 유지. 멤버 ListenerSet 포트 변경 → 0.7초 복귀, Envoy Service 포트 불변
- 함정 — Gateway API CRD는 보호 그룹(`*.k8s.io`)이라 `api-approved.kubernetes.io` annotation 없이는 거부(렌더 결과를 그대로 둘 것). CRD App과 CR App이 같은 커밋이면 CR App sync가 "failed to discover server resources"로 실패 → retry로 회복 — app-of-apps wave는 자식 App 생성 순서만 정하고 이미 있는 App의 자체 sync는 막지 못함 → CRD 묶음을 `bootstrap/`으로 분리. Git polling 3분이 전체 지연의 대부분(webhook 미설정)

## main 머지 때

- `apps/platform-rbac.yaml` targetRevision → main
- `bootstrap/appproject.yaml`에 destination `tech-neo-karmada` · sourceRepo docker.io/envoyproxy 추가, `karmada/bootstrap/appproject.yaml`(karmada-test) 폐기, `karmada/bootstrap/apiserver-crds-*.yaml`의 targetRevision → main
- hub `telox-platform-root` targetRevision → main
