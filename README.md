# gpu-workload-deploy — tech-neo-wkld 플랫폼 GitOps (Argo CD app-of-apps)

관리 클러스터 **tech-neo-mgmt**의 Argo CD(v3.5.5, ns `argocd`, `resourceTrackingMethod: annotation`)가 workload 클러스터
**tech-neo-wkld**(Argo CD cluster `tech-neo-wkld`, `https://10.7.56.210:6443`)의 플랫폼 구성 요소 전부를 관리한다.
helm · kubectl로 설치돼 돌던 것을 **재시작 · 중단 없이 채택(adopt)** 했다(2026-10-20, 결과는 [채택 결과](#채택-결과-2026-10-20)).

원본: `~/Documents/work/cursor-workspace/telox-tech-wkld-manifests-2026-10-13`(git 아님)의 `manifests/` · `values/`를 복사 — 설계 번호 · 주석 유지.
이 리포는 **public** — 비밀번호 · 토큰 · 인증서 · 개인키 · kubeconfig · SSH 공개키를 커밋하지 않는다(사설 IP 10.7.x는 테스트라 허용).

## 디렉터리 구조

```
bootstrap/                     hub에 손으로 apply (Argo CD가 관리하지 않음)
  appproject.yaml              AppProject telox-platform — 대상 tech-neo-wkld, 모든 ns · cluster-scoped 허용
  repositories.yaml            docker.io/envoyproxy OCI helm 저장소 선언(enableOCI, 자격 증명 없음)
  root-app.yaml                root Application telox-platform-root → apps/
apps/                          자식 Application 14개 (root가 directory source로 읽음)
platform/
  telox-crds/               00-crds.yaml(Domain · SKU · Instance), 02-serverlessinstance-crd.yaml
  chart-crds/<chart>-<ver>/    helm 차트 crds/ 디렉터리 복사본(gpu-operator · NFD, dra-driver, nri-topo, external-dns)
  system-rbac/                 01-system-rbac.yaml, 10-kyverno-rbac.yaml, 30-dcgm-exporter-dra-rbac.yaml
  kyverno-policies/            11 · 12 · 13 · 14 · 16 · 18 · 19 ValidatingPolicy, 15 ClusterPolicy
  deviceclass/                 04-deviceclass.yaml
  cilium-policies/             03-cilium.yaml (CCNP instance-egress, CiliumL2AnnouncementPolicy)
  gatewayclass/                22-gatewayclass.yaml (22-project-gateway-dev.yaml 중 GatewayClass만)
  charts/dra-driver-nvidia-gpu-v0.5.1/   upstream 차트 무수정 복사(UPSTREAM.md)
  values/                      helm values (release별 1개 + gateway-crds)
docs/adoption-2026-10-20/      채택 증빙(Pod 스냅샷 · wave별 비교 · Argo diff · DaemonSet 상태 · 기능 확인)
```

## Bootstrap (root apply)

```sh
export KUBECONFIG=~/.kube/tech-neo-mgmt.config
kubectl apply -f bootstrap/          # AppProject + OCI repo 선언 + root Application
```

root는 hub 자신(in-cluster `argocd` ns)에 Application을 쓰므로 project `default`, 자식은 project `telox-platform`.
root · 자식 모두 **finalizer 없음** — Application을 지워도 클러스터 리소스는 남는다(cascade 삭제 방지).

## Application 목록

| wave | Application | 출처 | 버전 | values / 경로 | ns (release) |
|---|---|---|---|---|---|
| 0 | telox-crds | 이 리포 | — | platform/telox-crds | — |
| 0 | gateway-crds | oci `docker.io/envoyproxy/gateway-crds-helm` | v1.9.2 | values/gateway-crds.yaml (gatewayAPI standard + envoyGateway) | — |
| 0 | chart-crds | 이 리포(차트 crds/ 복사본) | 차트 버전별 디렉터리 | platform/chart-crds (recurse) | — |
| 1 | system-rbac | 이 리포 | — | platform/system-rbac | telox-system 등 |
| 2 | kyverno | https://kyverno.github.io/kyverno `kyverno` | 3.7.1 (v1.17.1) | values/kyverno.yaml | kyverno (kyverno) |
| 3 | kyverno-policies | 이 리포 | — | platform/kyverno-policies | — |
| 4 | nri-topo | https://containers.github.io/nri-plugins `nri-resource-policy-topology-aware` | v0.14.0 | values/nri-topo.yaml | kube-system (nri-topo) |
| 4 | gpu-operator | https://helm.ngc.nvidia.com/nvidia `gpu-operator` | v26.7.2 | values/gpu-operator.yaml | gpu-operator (gpu-operator) |
| 4 | ndra | 이 리포 platform/charts/dra-driver-nvidia-gpu-v0.5.1 (upstream kubernetes-sigs/dra-driver-nvidia-gpu tag v0.5.1) | 0.5.1 | values/ndra.yaml | nvidia-dra-driver-gpu (ndra) |
| 5 | deviceclass | 이 리포 | — | platform/deviceclass | — |
| 5 | cilium-policies | 이 리포 | — | platform/cilium-policies | — |
| 6 | eg | oci `docker.io/envoyproxy/gateway-helm` | v1.9.2 | values/21-envoy-gateway-values.yaml | envoy-gateway-system (eg) |
| 6 | gatewayclass | 이 리포 | — | platform/gatewayclass | — |
| 6 | external-dns | https://kubernetes-sigs.github.io/external-dns/ `external-dns` | 1.23.0 (0.23.0) | values/23-external-dns-values.yaml | external-dns (external-dns) |

helm Application은 `helm.releaseName` · destination namespace를 기존 release와 같게 했다(다르면 리소스 이름이 바뀌어 채택이 아니라 재설치).
values는 multi-source(`ref: values` → `$values/platform/values/...`).

### 공통 설정
- `syncOptions`: `ServerSideApply=true`, `RespectIgnoreDifferences=true`, `CreateNamespace=true`(전용 ns를 쓰는 helm 5개만). ndra는 `managedNamespaceMetadata`로 PSA `privileged` label을 코드화.
- 비교: `argocd.argoproj.io/compare-options: ServerSideDiff=true` — API server dry-run으로 diff(기본값 · webhook 정규화 차이로 인한 가짜 diff 제거).
- `syncPolicy.automated: {selfHeal: true, prune: false}` — 채택(수동 sync + diff 검토) 완료 뒤 켬. **prune은 끈 채로 유지**: 리포에서 지운 리소스는 손으로 정리.
- `ignoreDifferences` 없음 — 채택 시 전 Application이 tracking annotation 외 diff 0이라 필요 없었다.
- CRD는 helm 차트 crds/에 맡기지 않는다: 차트 Application은 `skipCrds: true`, CRD는 wave 0의 telox-crds · gateway-crds · chart-crds.
  예외: Kyverno CRD는 차트 `templates/`(crds subchart)에 있어 Application kyverno에 남김.
- sync wave는 root가 자식 Application을 만들 때의 순서. Argo CD 기본 설정에는 Application health check가 없어 root가 자식의 Healthy를 기다리지 않는다
  (처음부터 재설치할 때 순서를 강제하려면 hub argocd-cm에 `resource.customizations.health.argoproj.io_Application` 추가 — 남은 과제).
  대신 자식마다 `retry`(5회, 10s→3m backoff)로 CRD 미존재 같은 순서 문제를 흡수한다.

### 제외(GitOps 대상 아님, 클러스터에 그대로)
Cilium helm release(bootstrap 몫, 참고 values는 원본 `values/cilium-extra.yaml`), Domain · SKU · Instance · ServerlessInstance CR,
domain-a/b/c ns와 그 안의 Domain reconcile 산출물(RoleBinding · ResourceQuota · default-deny · LB pool), Instance Pod · Service · NetworkPolicy · ResourceClaim,
Karmada 오브젝트(karmada-system · karmada-cluster, `karmada.io/managed=true`), project Gateway 테스트 오브젝트(EnvoyProxy ep-dev · Gateway gw-dev · route · ListenerSet · Secret wildcard-r1 · Envoy Deployment/Service),
`smoke/`, `values/gpu-operator-dev-region-*.yaml`, `values/driver-repo-snapshot.yaml`, 노드 호스트 설정(`host/`).
원본 `manifests/20-gateway-api-crds.yaml`(1.1MB)은 gateway-crds-helm으로 대체해 복사하지 않음(렌더 20개 오브젝트가 원본과 동일).

## Route53 전환 (external-dns)

`platform/values/23-external-dns-values.yaml`에서 provider 블록과 관련 값만 바꾼다. 자격 증명은 이 리포에 넣지 말고 클러스터 Secret(또는 IRSA/Pod Identity)으로:

```yaml
provider:
  name: aws
env:
  - name: AWS_DEFAULT_REGION
    value: ap-northeast-2
  - name: AWS_SHARED_CREDENTIALS_FILE        # 정적 키를 쓸 때만 — Secret은 리포 밖에서 생성
    value: /etc/aws/credentials
extraVolumes:
  - name: aws-credentials
    secret: {secretName: external-dns-aws}  # kubectl로 별도 생성(리포에 커밋 금지)
extraVolumeMounts:
  - {name: aws-credentials, mountPath: /etc/aws, readOnly: true}
extraArgs:
  - --aws-zone-type=public
  - --gateway-label-filter=tktech.thakicloud.io/dns-source=true
  # --inmemory-zone 삭제
domainFilters: [<실제 zone>]                # neo.test → 실제 zone
txtOwnerId: tech-neo-wkld                   # 유지(다른 클러스터와 겹치지 않게)
```

`sources`(gateway-httproute · gateway-tlsroute), `policy: sync`, `enableGatewayListenerSets`는 그대로.
gateway-tcproute는 ExternalDNS가 TCPRoute v1을 읽는 릴리스(upstream PR #6755 포함)로 올린 뒤 복귀.

## 운영 메모 (함정)

- **gpu-operator**: driver DaemonSet은 operator가 ClusterPolicy에서 만든다(Argo가 추적하지 않음 — tracking annotation 없음 정상). values를 바꿔 ClusterPolicy의 driver 관련 값이 바뀌면
  driver DaemonSet 템플릿이 바뀌고(OnDelete라 Pod는 그대로) ClusterPolicy가 notReady가 된다. driver Pod를 재생성하면 **DRA kubelet plugin(ns nvidia-dra-driver-gpu)도 재시작**해야 한다
  (안 하면 claim CDI spec에 device node · 라이브러리가 빠짐 — 원본 README 2026-10-16). automated라 merge = 반영이므로 driver 관련 values 변경은 GPU Pod 정비 창에서만.
- **eg**: certgen Job · topology-injector MutatingWebhookConfiguration은 helm `pre-install,pre-upgrade` hook → Argo **PreSync hook**으로 eg가 sync될 때마다 다시 돈다.
  certgen은 기존 Secret을 덮어쓰지 않고(`--overwrite` 없음) webhook caBundle을 기존 CA로 patch — helm upgrade와 같은 동작. webhook은 `failurePolicy: Ignore` · envoy-gateway-system의 pods/binding만이라 재생성 순간의 영향 없음.
- **gpu-operator hook 끔**(values): `operator.upgradeCRD: false`(PreSync로 sync마다 CRD apply Job), `node-feature-discovery.postDeleteCleanup: false`
  (PostDelete로 Application 삭제 시 NFD node label 삭제 → GPU node 인식 상실 위험). 둘 다 hook만 빠지고 일반 리소스 렌더 결과는 동일.
  남은 hook `gpu-operator-cleanup-gpucluster`(pre-delete)와 Kyverno의 pre-delete · test hook은 Argo CD가 지원하지 않아 무시된다.
- **CRD 버전 올리기**: 차트 버전을 올리면 `platform/chart-crds/<chart>-<새 버전>/`에 crds/를 복사하고 옛 디렉터리를 지운다(prune false라 CRD 삭제는 일어나지 않음 — 의도).
- **ndra 차트**는 upstream 리포를 직접 참조하지 않는다(hub repo-server fetch timeout). 버전 올리기는 `platform/charts/dra-driver-nvidia-gpu-v0.5.1/UPSTREAM.md`.
- hub의 `argocd-initial-admin-secret`은 삭제돼 있다. 이번 작업은 `argocd --core`(KUBECONFIG = tech-neo-mgmt, context namespace `argocd`)로 했다. 로컬 argocd CLI 기본 context는 다른 서버를 가리키므로 `ARGOCD_CONFIG_DIR`을 따로 둘 것.

## 채택 결과 (2026-10-20)

절차: Pod 스냅샷 → `kubectl apply -f bootstrap/` → root sync(자식 14개 생성, 자식은 수동) → Application별 `argocd app diff` 검토 → wave 순서 수동 sync, wave마다 Pod 비교 → 기능 확인 → automated 전환 → 리포 값 변경 반영 확인.
사전 검증으로 각 helm release는 `helm template`(같은 차트 · values · kube-version · api-versions) 결과가 `helm get manifest`와 hook 외 diff 0, 모든 매니페스트는
`kubectl diff --server-side --field-manager=argocd-controller`(dry-run) diff 0을 먼저 확인했다.

### Application별 상태

| Application | wave | sync 시각(KST) | 소요 | 결과 | Argo diff(sync 전) |
|---|---|---|---|---|---|
| telox-crds | 0 | 16:21 · 16:22 | 1s ×2 | Synced · Healthy | 0 → sync 뒤 `last-applied-configuration` 제거 diff(아래 ①), 2차 sync |
| gateway-crds | 0 | 16:21 | 2s | Synced · Healthy | tracking annotation만 |
| chart-crds | 0 | 16:21 | 1s | Synced · Healthy | computedomains CRD 스키마(아래 ②) |
| system-rbac | 1 | 16:21 | 0s | Synced · Healthy | tracking annotation만 |
| kyverno | 2 | 16:22 | 24s | Synced · Healthy | tracking annotation만(아래 ③) |
| kyverno-policies | 3 | 16:24 | 1s | Synced · Healthy | tracking annotation만 |
| nri-topo | 4 | 16:25 | 0s | Synced · Healthy | tracking annotation만(아래 ④) |
| ndra | 4 | 16:25 | 3s | Synced · Healthy | tracking annotation만(아래 ⑤) |
| gpu-operator | 4 | 16:26 | 1s | Synced · Healthy | tracking annotation만 — ClusterPolicy · driver DaemonSet diff 0 |
| deviceclass | 5 | 16:28 | <1s | Synced · Healthy | tracking annotation만 |
| cilium-policies | 5 | 16:28 | <1s | Synced · Healthy | tracking annotation만 |
| eg | 6 | 16:28 | 51s(certgen hook 포함) | Synced · Healthy | tracking annotation만(아래 ⑥) |
| gatewayclass | 6 | 16:30 | <1s | Synced · Healthy | tracking annotation만 |
| external-dns | 6 | 16:30 | <1s | Synced · Healthy | tracking annotation만 |

sync 전 diff 원문: `docs/adoption-2026-10-20/argocd-diff-before-sync/`.

### diff 0이 아니었던 항목과 처리
1. **telox-crds — `kubectl.kubernetes.io/last-applied-configuration`**: 원래 client-side `kubectl apply`로 설치. 첫 SSA sync에서 Argo CD가 client-side apply 필드 소유권을
   argocd-controller로 옮긴 뒤 desired에 없는 이 annotation이 diff로 떠 2차 sync로 제거(metadata만). system-rbac 등 다른 kubectl 매니페스트는 SSA로 적용돼 있어 해당 없음.
2. **chart-crds — `computedomains.resource.nvidia.com`**: 클러스터의 CRD는 ndra 첫 설치(차트 25.12.0) 것 — helm upgrade는 crds/를 갱신하지 않아 0.5.1로 올린 뒤에도 남아 있었다.
   0.5.1 내용(gpu-operator v26.7.2 동봉본과 동일)으로 갱신: `numNodes` default 0 · minimum 0 · required 해제(완화). ComputeDomain 오브젝트 0개 · computeDomains off라 영향 없음.
3. **kyverno — Deployment generation +1 (4개)**: 차트가 `replicas:`를 null로 렌더 → SSA 적용 시 generation만 증가. 템플릿 해시 · ReplicaSet · Pod 변화 없음(revision 그대로, `restartedAt`은 kubectl-rollout 소유로 유지).
4. **nri-topo — `ENABLE_TEST_APIS=1`**: 우려와 달리 diff 없음. 차트 v0.14.0 `daemonset.yaml`의 `{{- if ".Values.plugin-test.enableAPIs" }}`가 따옴표로 감싼 문자열이라 항상 참 →
   차트가 ENABLE_TEST_APIS="1"을 무조건 렌더한다. 실제 DaemonSet은 generation 1 · managedFields helm뿐(`kubectl set env`는 no-op). values · Kustomize patch · ignoreDifferences 모두 불필요.
5. **ndra — 차트 출처**: upstream git(`kubernetes-sigs/dra-driver-nvidia-gpu` tag v0.5.1)을 직접 쓰면 hub repo-server가 `git fetch --tags`에서 exec timeout 1m30s → ComparisonError 반복.
   차트 디렉터리(168KB, Apache-2.0)를 `platform/charts/dra-driver-nvidia-gpu-v0.5.1`에 무수정 복사(commit b04b4153)해 해결.
6. **eg — hook 재실행**: PreSync hook으로 certgen Job 실행 + topology-injector webhook 재생성(UID 변경). Secret 4개 resourceVersion 불변, webhook caBundle = 기존 `envoy-gateway` ca.crt 확인.
   values에 `crds.enabled: false` 추가 — `skipCrds`는 crds/만 빼고 subchart templates의 safe-upgrades VAP는 렌더하므로(그대로 두면 gateway-crds와 같은 리소스를 두 Application이 소유).
7. **gpu-operator — values 2개 추가**(hook만 제거, 렌더 diff 0): 위 운영 메모.

### 재시작 0건 증빙
- 채택 전 스냅샷(16:00, `pods-before.*`)과 wave마다 · 최종(`pods-final.tsv`)을 namespace/name · UID · `status.startTime` · restartCount로 비교: `podcheck-per-wave.txt`.
- **Instance Pod**(domain-a gpu-a · cpu-a, domain-b cpu-b1 · cpu-b2), **driver** · **dcgm-exporter** · **DRA kubelet plugin** · **nri** · **Envoy**(envoy-gateway, envoy-domain-a-gw-dev) ·
  Kyverno · gpu-operator · NFD · external-dns 등 **55개 중 52개가 UID · startTime · restartCount 그대로**, 교체 · 신규 Pod 0(certgen hook Pod는 완료 후 정리).
- driver DaemonSet(gen 3 · OnDelete · ControllerRevision rev 3) · DRA plugin(gen 1, rev 1) · nri(gen 1) · dcgm(gen 3) · ClusterPolicy(gen 4, ready) 모두 sync 전후 동일: `ds-before-wave4.txt` = `ds-final.txt`.
- 재시작이 늘어난 3개는 **GitOps 범위 밖이고 Argo가 건드리지 않은** kube-system Pod: kube-vip cp-1(51→53) · cp-3(46→47), cilium-operator(74→75).
  kube-vip ARP manager panic(exit 2)으로 apiserver VIP 10.7.56.210이 흔들려 cilium-operator가 lease 갱신 timeout → leader election lost(exit 255). 첫 kube-vip 재시작은 자식 sync 전(16:20 이전)에 이미 발생 —
  채택 전에도 7일간 kube-vip 34–51회 · cilium-operator 74회 · kube-scheduler/controller-manager 8–28회 재시작하던 기존 현상(GitOps 대상 아님).

### 기능 확인 (`functional-after-manual.txt`)
- `kubectl get clusterpolicies.nvidia.com` → cluster-policy **ready**
- Kyverno ValidatingPolicy 7 · ClusterPolicy 1 전부 Ready
- `kubectl -n domain-a get gateway gw-dev` → Programmed True(10.7.56.70)
- `curl -k --resolve a-80-dev-a.r1.neo.test:443:10.7.56.70 https://a-80-dev-a.r1.neo.test/` → **200**
- `kubectl --kubeconfig ~/.kube/tech-neo-karmada.config get clusters` → tech-neo-wkld Ready
- automated 전환(16:31, root auto-sync, 자식 재sync 없음) 뒤 `platform/deviceclass/04-deviceclass.yaml`에 label `telox.io/gitops: argocd` 추가 → push 5초 뒤 automated sync로 반영(rev c0649d6).

## 남은 과제
- **운영용 전용 SA**: Argo CD cluster Secret이 client 인증서(tlsClientConfig, kubeadm admin 계열)로 붙어 있다 → 대상 클러스터에 Argo 전용 SA + 필요한 권한만의 ClusterRole · bearer token으로 교체.
- **Route53**: external-dns provider 전환(위 블록), 자격 증명은 리포 밖.
- **wave 강제**: hub argocd-cm에 Application health check 추가(hub Argo CD helm values에서) — 지금은 retry로 흡수.
- hub `argocd-initial-admin-secret` 삭제 상태 — UI/API 로그인 수단(SSO 또는 admin 비밀번호 재설정) 정리.

## 진짜 배포 (2026-10-20) — 빈 클러스터에서 root 하나로 전부 설치

채택(위)과 별개로, 리포가 곧 클러스터 정의인지 확인하기 위해 wkld를 비우고 다시 설치했다. 증빙은 `docs/fresh-deploy-2026-10-20/`.

- **비운 범위**: Instance 4개 · project gateway 오브젝트 · Domain a/b(namespace GC) · SKU · DeviceClass · Kyverno 정책 · Cilium CR · helm 릴리스 6개(`--no-hooks`) · webhook · namespace · ClusterRole · CRD(cilium.io 제외 34개). 남긴 것은 Cilium · kube-vip · karmada-agent. hub 쪽 Application 15개도 먼저 삭제(cascade 없음).
  - kyverno Application 삭제가 멈춤: 차트 pre-delete hook Job이 cp · GPU taint에 toleration이 없어 Pending → Argo `pre-delete-finalizer`가 안 풀림. finalizer를 직접 제거. 운영에서는 hook Job에 toleration을 주거나 `argocd.argoproj.io/hook-delete-policy`로 처리 필요.
- **hub 변경**: argocd-cm에 `resource.customizations.health.argoproj.io_Application`(Lua) 추가. 자식 Application이 Synced가 아니면 Progressing으로 보고해 root가 wave 순서를 실제로 기다림. 없으면 자식 14개가 동시에 생성돼 CRD보다 CR이 먼저 들어가 retry로 흡수되는 구조였다.
- **배포**: `kubectl apply -f bootstrap/` 19:01:08 → 15개 Synced · Healthy 19:05:18 (4분 10초). wave별 READY 시각은 `app-ready-order.txt`.

| wave | Application | READY(KST) |
|---|---|---|
| 0 | chart-crds · gateway-crds | 19:02:17 |
| 0 · 1 | telox-crds · system-rbac | 19:02:37 |
| 2 · 3 · 4 | kyverno · kyverno-policies · nri-topo | 19:04:38 |
| 4 · 5 | gpu-operator · ndra · deviceclass · cilium-policies | 19:04:58 |
| 6 | eg · external-dns · gatewayclass · root | 19:05:18 |

- **기능 확인**(`functional-after-fresh.txt`): gpu-operator ClusterPolicy **ready 19:07:04**(Application Healthy보다 2분 뒤 — operand는 ClusterPolicy 뒤에 생기므로 Application health가 driver 준비를 뜻하지 않음), driver · toolkit · dcgm · validator Running, cuda-validator Succeeded, DRA kubelet plugin Running + ResourceSlice gpu-0, DeviceClass 4개(telox-h100 포함), nri 1/1 ENABLE_TEST_APIS=1, Kyverno ValidatingPolicy 7개 ready, webhook 11개, GatewayClass Accepted, external-dns Running, Cilium CR 2개, SA 3 · ClusterRole 5, CRD 66, Karmada 멤버 Ready(telox API 재수집).
- **결론**: 리포만으로 플랫폼 전체가 재현된다. Domain · SKU · Instance는 GitOps 밖이므로 지금 클러스터에는 없다(Karmada 또는 telox-manager 경로로 생성).

### 순서 보강 (2026-10-20, 진짜 배포 뒤)
- 진짜 배포에서 ndra(wave 4)의 DRA kubelet plugin이 driver pod보다 먼저 떴다(plugin 19:04:26 · driver 시작 19:04:32 · driver Ready 19:05:42). plugin의 init-container가 `/run/nvidia/driver`에 nvidia-smi · libnvidia-ml이 생길 때까지 재시도해 결과는 정상이었고, full GPU claim probe로 devnode 5개 · libcuda/libnvidia-ml 580.159.03 · `nvidia-smi -L` H100 NVL 주입을 확인했다(`docs/fresh-deploy-2026-10-20/`).
- 우연에 기대지 않도록 둘을 고정: hub argocd-cm에 `nvidia.com/ClusterPolicy` health check(state ready → Healthy, 아니면 Progressing)를 추가해 gpu-operator Application이 driver 스택 준비 뒤에만 Healthy가 되게 했고, `apps/ndra.yaml`을 wave 5로 내렸다. 이제 root는 driver ready 뒤에 ndra를 만든다.
- driver pod가 **재생성**될 때 plugin을 재시작해야 하는 규칙은 별도(설계 Appendix) — GitOps 순서와 무관하게 gpu-operator 업그레이드 절차에서 지킬 것.

## wkld 클러스터 추가(멀티 클러스터) — main(2026-10-28 karmada-argocd-test 머지)

1. 등록 — `karmadactl register … --cluster-name <name> --cluster-region <region> --cluster-provider openstack --cluster-zones <zone>` (worker에 taint가 있으면 agent Deployment toleration patch)
2. 직접 경로 — Argo cluster Secret에 label `telox.io/role=wkld` · `telox.io/region=<region>` · `telox.io/gpu=true|false`(false면 gpu-operator · ndra · nri-topo 생략) + AppProject `telox-platform` destinations에 이름 추가 → `bootstrap/applicationset.yaml`(cluster generator)이 `telox-platform-<name>` root Application을 만들고 `apps-chart/`를 렌더(Application 이름 접두사 = 클러스터 이름)
3. 플랫폼 App이 전부 Synced · Healthy가 된 **뒤에** Karmada Cluster label `telox.io/role=wkld` · `telox.io/region=<region>` — Karmada는 Cluster 변경 이벤트에만 전 binding을 재스케줄하고 멤버 apiEnablements 갱신엔 하지 않으므로, 먼저 label을 붙였으면 플랫폼 완료 뒤 label을 하나 더 바꿔 재트리거
4. domain 배치 — `karmada/domain-<x>/`에 namespace(skip label) · Domain · project Gateway + ClusterPropagationPolicy `clusterNames: [<name>]`, Instance는 `karmada/instances-<x>/`. region 전용 SKU는 CPP `fieldSelector region In [<region>]`. 클러스터별 값 차이는 ClusterOverridePolicy(targetCluster label) — **전파 전에** 선언(SKU처럼 불변 kind는 나중에 붙이면 멤버가 거부)
5. tech L2 환경 — Envoy pod와 Cilium L2 announce가 같은 node여야 함(eTP Local). edge node에 `telox.io/edge=true` + pool label 1개만, EnvoyProxy nodeSelector edge. ExternalDNS `txtOwnerId`는 클러스터별로 달라야 함(현재 values 공통 — 미반영)
