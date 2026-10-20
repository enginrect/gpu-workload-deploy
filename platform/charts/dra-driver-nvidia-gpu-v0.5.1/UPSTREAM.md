# Vendored chart — dra-driver-nvidia-gpu 0.5.1

- upstream: https://github.com/kubernetes-sigs/dra-driver-nvidia-gpu
- tag `v0.5.1` (commit `b04b41531423b490cc01b5d196d9955b9b862878`), path `deployments/helm/dra-driver-nvidia-gpu` — 무수정 복사(이 파일만 추가). License: Apache-2.0 (LICENSE).
- 복사 이유: hub(tech-neo-mgmt) repo-server가 upstream 리포 전체(vendor/ 포함 · 태그 전부)를 `git fetch`하다 exec timeout 1m30s에 걸려
  manifest 생성이 영원히 실패(ComparisonError DeadlineExceeded, 2026-10-20). NGC helm 저장소엔 25.x만 있어 차트 저장소 대안도 없음.
- 버전을 올릴 때: 새 태그의 같은 경로를 `dra-driver-nvidia-gpu-v<ver>/`로 복사하고 apps/ndra.yaml의 path를 바꾼다(crds/ 변경은 platform/chart-crds에도 반영).
