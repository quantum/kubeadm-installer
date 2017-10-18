#!/usr/bin/env bash


# Params
# --
distro=${1}
action=${2:-install}


# Variables
# --
#
# These values can be overridden by ENV Vars
#
K8S_REPO="kubernetes/kubernetes"

# Example
#K8S_VERSION=${K8S_VERSION:-v1.6.1}
K8S_VERSION=${K8S_VERSION:-}

# Example
#KUBEADM_RELEASE=${KUBEADM_RELEASE:-v1.6.0-alpha.0.2074+a092d8e0f95f52}
KUBEADM_RELEASE=${KUBEADM_RELEASE:-}

# Example
#CNI_RELEASE=${CNI_RELEASE:-07a8a28637e97b22eb8dfe710eeae1344f69d16e}
CNI_RELEASE=${CNI_RELEASE:-}
CNI_REPO="containernetworking/cni"
CNI_PLUGINS_REPO="containernetworking/plugins"

# Installer variables
ARCH=${ARCH:-amd64}
CNI_BIN_DIR=${CNI_BIN_DIR:-/opt/cni}
ROOTFS=${ROOTFS:-/rootfs}


# Helpers
# --
fail()
{
  echo "$*"
  exit 1
}

usage()
{
  cat <<-EOF
	  Hi, you should run this container like this:
	  docker run -it \
	    -v /etc/:/rootfs/etc \
	    -v /usr:/rootfs/usr \
	    -v /opt:/rootfs/opt \
	    xakra/kubeadm-installer your_os_here

	  your_os_here can be coreos, ubuntu, debian, fedora or centos

	  You can also revert this action with running:
	  docker run -it \
	    -v /etc/:/rootfs/etc \
	    -v /usr:/rootfs/usr \
	    -v /opt:/rootfs/opt \
	    xakra/kubeadm-installer your_os_here uninstall
	EOF
}

get_git_latest_release() {
  local url="https://api.github.com/repos/${1}/releases/latest"
  curl --silent ${url} | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' || \
    fail "Failed to get latest release from ${url}"
}

print_systemd() {
	echo $FUNCNAME $@
	local action=$1

	[[ install == "$action" ]] \
  	&& cat <<- EOF
	Done! Now run this in your terminal to enable docker and kubelet:

	systemctl daemon-reload
	systemctl enable docker kubelet
	systemctl restart docker kubelet
	EOF

	[[ uninstall == "$action" ]] \
  	&& cat <<- EOF
	Done! Now run this in your terminal to complete the uninstall:

	systemctl daemon-reload
	systemctl disable kubelet
	EOF

	exit 0
}


# Handle no values for Versions
# --
# If no values are provided, get the latest release of k8s
if [[ -z "${K8S_VERSION}" ]]; then
  echo "[ENV] 'K8S_VERSION' is empty -> Getting latest release version"
  K8S_VERSION=$(get_git_latest_release $K8S_REPO)
fi
echo "[ENV] 'K8S_VERSION' = ${K8S_VERSION}"

# If no values are provided, use the same than k8s
if [[ -z "${KUBEADM_RELEASE}" ]]; then
  echo "[ENV] 'KUBEADM_RELEASE' is empty -> Getting same version as k8s"
  KUBEADM_RELEASE=${K8S_VERSION}
fi
echo "[ENV] 'KUBEADM_RELEASE' = ${KUBEADM_RELEASE}"

# If no values are provided, get the latest release of CNI
if [[ -z "${CNI_RELEASE}" ]]; then
  echo "[ENV] 'CNI_RELEASE' is empty -> Getting latest release version"
  CNI_RELEASE=$(get_git_latest_release $CNI_REPO)
fi
echo "[ENV] 'CNI_RELEASE' = ${CNI_RELEASE}"


# Kubernetes Google Cloud Storage
# --
#
# Handling usage of Dev / Final release buckets
#
K8S_URL=${K8S_URL:-https://storage.googleapis.com/kubernetes-release/release}

echo "[Kubeadm] Selected version: ${KUBEADM_RELEASE}"
if [[ -z "${KUBEADM_URL}" ]]; then
  if [[ -n "${KUBEADM_VERSION/v[0-9].[0-9].[0-9]/}" ]]; then
    echo "[Kubeadm] KUBEADM_RELEASE ${KUBEADM_RELEASE} is a Pre-release version"
    KUBEADM_URL=https://storage.googleapis.com/kubernetes-release-dev/ci-cross
  else
    echo "[Kubeadm] KUBEADM_RELEASE ${KUBEADM_RELEASE} is a Release version"
    KUBEADM_URL=https://storage.googleapis.com/kubernetes-release/release
  fi
fi
echo "[Kubeadm] Download url: ${KUBEADM_URL}"

# To find out if the CNI_RELEASE is available on Google Cloud Storage:
# `$ docker run --rm -ti google/cloud-sdk gsutil ls gs://kubernetes-release/network-plugins`
#
echo "[CNI] Selected version: ${CNI_RELEASE}"
if [[ -z "${CNI_URL}" ]]; then
  if [[ -n "${CNI_RELEASE/v[0-9].[0-9].[0-9]/}" ]]; then
    echo "[CNI] CNI_RELEASE ${CNI_RELEASE} is a Pre-release version"
    CNI_URL=https://storage.googleapis.com/kubernetes-release/network-plugins/cni-${ARCH}-${CNI_RELEASE}.tar.gz
  else
    echo "[CNI] CNI_RELEASE ${CNI_RELEASE} is a Release version"
    CNI_URL=https://github.com/${CNI_REPO}/releases/download/${CNI_RELEASE}/cni-${ARCH}-${CNI_RELEASE}.tgz
    if [[ -n "${CNI_RELEASE/v0.[0-5].[0-9]/}" ]]; then
      CNI_PLUGINS_URL=https://github.com/${CNI_PLUGINS_REPO}/releases/download/${CNI_RELEASE}/cni-plugins-${ARCH}-${CNI_RELEASE}.tgz
    fi
  fi
fi
echo "[CNI] Download url: ${CNI_URL}"
if [[ -n "${CNI_PLUGINS_URL}" ]]; then
  echo "[CNI] Plugins download url: ${CNI_PLUGINS_URL}"
fi



# Linux Distro
# --
#
# Environment settings according to Distro
#
case ${distro} in
coreos)
  BIN_DIR=${BIN_DIR:-/opt/bin}
  KUBELET_EXEC=${KUBELET_EXEC:-/usr/lib/coreos/kubelet-wrapper}
  EXTRA_ENVIRONMENT=${EXTRA_ENVIRONMENT:-"RKT_RUN_ARGS=\
--volume opt-cni,kind=host,source=/opt/cni \
--mount volume=opt-cni,target=/opt/cni \
--volume etc-cni,kind=host,source=/etc/cni \
--mount volume=etc-cni,target=/etc/cni"}
  INSTALL_KUBELET=0
  ;;

ubuntu|debian|fedora|centos)
  BIN_DIR=${BIN_DIR:-/usr/bin}
  KUBELET_EXEC=${KUBELET_EXEC:-${BIN_DIR}/kubelet}
  EXTRA_ENVIRONMENT=${EXTRA_ENVIRONMENT:-"NOOP=true"}
  INSTALL_KUBELET=1
  ;;

*)
  usage
  exit 1
  ;;
esac


# Main
# --
set -o errexit
set -o nounset

if [[ ${action} == "uninstall" ]]; then
  rm -rfv ${ROOTFS}/etc/cni \
    ${ROOTFS}/${BIN_DIR}/kubectl \
    ${ROOTFS}/${BIN_DIR}/kubelet \
    ${ROOTFS}/${BIN_DIR}/kubeadm \
    ${ROOTFS}/${CNI_BIN_DIR} \
    ${ROOTFS}/etc/systemd/system/kubelet.service

	print_systemd uninstall
fi


# Install
#
mkdir -p ${ROOTFS}/etc/cni \
  ${ROOTFS}/${BIN_DIR}

if [[ ! -f ${ROOTFS}/${BIN_DIR}/kubectl ]]; then
  echo "Downloading kubectl to ${BIN_DIR}/kubectl"
  if curl -sSL ${K8S_URL}/${K8S_VERSION}/bin/linux/${ARCH}/kubectl > ${ROOTFS}/${BIN_DIR}/kubectl; then
    chmod +x ${ROOTFS}/${BIN_DIR}/kubectl
    echo "Installed kubectl in ${BIN_DIR}/kubectl"
  else
    rm -f ${ROOTFS}/${BIN_DIR}/kubectl
    fail "Failed to download kubectl"
  fi
else
  echo "Ignoring ${BIN_DIR}/kubectl, since it seems to exist already"
fi

if [[ ${INSTALL_KUBELET} == 0 ]]; then
  true;
elif [[ ! -f ${ROOTFS}/${BIN_DIR}/kubelet ]]; then
  echo "Downloading kubelet to ${BIN_DIR}/kubelet"
  if curl -sSL ${K8S_URL}/${K8S_VERSION}/bin/linux/${ARCH}/kubelet > ${ROOTFS}/${BIN_DIR}/kubelet; then
    chmod +x ${ROOTFS}/${BIN_DIR}/kubelet
    echo "Installed kubelet in ${BIN_DIR}/kubelet"
  else
    rm -f ${ROOTFS}/${BIN_DIR}/kubelet
    fail "Failed to download kubelet"
  fi
else
  echo "Ignoring ${BIN_DIR}/kubelet, since it seems to exist already"
fi

if [[ ! -f ${ROOTFS}/${BIN_DIR}/kubeadm ]]; then
  echo "Downloading kubeadm to ${BIN_DIR}/kubeadm"
  if curl -sSL ${KUBEADM_URL}/${KUBEADM_RELEASE}/bin/linux/${ARCH}/kubeadm > ${ROOTFS}/${BIN_DIR}/kubeadm; then
    chmod +x ${ROOTFS}/${BIN_DIR}/kubeadm
    echo "Installed kubeadm in ${BIN_DIR}/kubeadm"
  else
    rm -f ${ROOTFS}/${BIN_DIR}/kubeadm
    fail "Failed to download kubeadm"
  fi
else
  echo "Ignoring ${BIN_DIR}/kubeadm, since it seems to exist already"
fi

if [[ ! -d ${ROOTFS}/${CNI_BIN_DIR} ]]; then
  mkdir -p ${ROOTFS}/${CNI_BIN_DIR}
  echo "Downloading CNI binaries to ${CNI_BIN_DIR}"
  if curl -sSL ${CNI_URL} | tar -xz -C ${ROOTFS}/${CNI_BIN_DIR}; then
    echo "Installed CNI binaries in ${CNI_BIN_DIR}"
    if [[ -n "${CNI_PLUGINS_URL}" ]]; then
      echo "Downloading CNI plugins to ${CNI_BIN_DIR}"
      if curl -sSL ${CNI_PLUGINS_URL} | tar -xz -C ${ROOTFS}/${CNI_BIN_DIR}; then
        echo "Installed CNI plugins in ${CNI_BIN_DIR}"
      else
        rm -rf ${ROOTFS}/${CNI_BIN_DIR}
        fail "Failed to download CNI plugins"
      fi
    fi
  else
    rm -rf ${ROOTFS}/${CNI_BIN_DIR}
    fail "Failed to download CNI binaries"
  fi
else
  echo "Ignoring ${CNI_BIN_DIR}, since it seems to exist already"
fi

if [[ ! -f ${ROOTFS}/etc/systemd/system/kubelet.service ]]; then
  mkdir -p -v ${ROOTFS}/etc/systemd/system/

  cat > ${ROOTFS}/etc/systemd/system/kubelet.service <<-EOF
  [Unit]
  Description=kubelet: The Kubernetes Node Agent
  Documentation=http://kubernetes.io/docs/

  [Service]
  Environment="KUBELET_VERSION=${K8S_VERSION}_coreos.0"
  Environment="KUBELET_IMAGE_TAG=${K8S_VERSION}_coreos.0"
  Environment="${EXTRA_ENVIRONMENT}"
  ExecStart=${KUBELET_EXEC} --kubeconfig=/etc/kubernetes/kubelet.conf \
    --require-kubeconfig=true \
    --pod-manifest-path=/etc/kubernetes/manifests \
    --allow-privileged=true \
    --network-plugin=cni \
    --cni-conf-dir=/etc/cni/net.d --cni-bin-dir=${CNI_BIN_DIR} \
    --cluster-dns=10.96.0.10 --cluster-domain=cluster.local
  Restart=always
  StartLimitInterval=0
  RestartSec=10

  [Install]
  WantedBy=multi-user.target
EOF
  echo "Installed the kubelet.service in /etc/systemd/system/kubelet.service"
else
  echo "Ignoring /etc/systemd/system/kubelet.service, since it seems to exist already"
fi

print_systemd install
