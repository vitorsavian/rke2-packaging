# rke2-packaging
Packaging repository for RKE2

## SLE packaging

SLE (SLES 16 / openSUSE Leap 16) recipes are based on SLE Micro, with the
same environment defaults and external SELinux dependency, following the
`rpm/<os>/<component>` layout:

- [Common package](rpm/sle/common/rke2-common.spec) and [fapolicyd rules](rpm/sle/common/80-rke2.rules).
- [Server package](rpm/sle/server/rke2-server.spec) and [agent package](rpm/sle/agent/rke2-agent.spec), with the same environment defaults as SLE Micro.

`make sle-build TAG=<packaging-tag> COMBARCH=x86_64-amd64` builds the common,
server and agent components using [Dockerfile.sle](Dockerfile.sle), as for
SLE Micro. The SELinux policy is not built or published by these scripts.
The common package depends on the externally maintained `rke2-selinux` RPM,
using the shared `rke2_policyver` requirement.

Binary RPMs are emitted under `dist/sle/<rpmarch>` and source RPMs under
`dist/sle/source`, with the `.sle` release suffix. Other OS recipes and SELinux
dependencies remain unchanged.

SELinux policy sources and policy RPM packaging belong in the SELinux policy
repository. The fapolicyd rules here are separate from SELinux policy.

These recipes target SLE, not transactional SLE Micro. Transactional systems
must use their own OS packaging and reboot after a transactional update.

## Versioning/Tagging

The version parsing logic for `rancher/rke2-packaging` expects tags to be of a certain format (that directly correlates to RKE2 version)

The following list shows the expected tag to (example) transformation for RPM's

|Tag|Tree State|Output RPM|RPM Channel|Notes|
|:--|:---------|:---------|:----------|:----|
| master (no tag) | Clean | `rke2-common-1.18.4~alpha8~0d52f7d8~rke2r1-0.el7.x86_64.rpm` | Testing | When building with a clean tree on master, it will automatically grab the latest listed release in `rancher/rke2` (pre-release or not)|
| master (no tag) | Dirty | `rke2-common-1.18.4~alpha8~0d52f7d8dirty~rke2r1-0.el7.x86_64.rpm` | Testing | When building with a clean tree on master, it will automatically grab the latest listed release in `rancher/rke2` (pre-release or not)|
| v1.18.4-alpha8+rke2r1.latest.0 | Clean | `rke2-common-1.18.4~alpha8~rke2r1-0.el7.x86_64.rpm` | Latest ||
| v1.18.4-alpha8+rke2r1.latest.1 | Clean | `rke2-common-1.18.4~alpha8~rke2r1-1.el7.x86_64.rpm` | Latest ||
| v1.18.4+rke2r1.stable.0 | Clean | `rke2-common-1.18.4~rke2r1-0.el7.x86_64.rpm` | Stable ||
| v1.18.4+rke2r1.stable.1 | Clean | `rke2-common-1.18.4~rke2r1-1.el7.x86_64.rpm` | Stable ||
