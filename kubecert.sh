!/bin/bash
red=$(tput setaf 1)
green=$(tput setaf 2)
reset=$(tput sgr0)
TMPDIR=$(mktemp -d)
function helpmenu() {
    echo "Usage: ./kubecert.sh [-y]
-y  When specified kubecert.sh will automatically install kubectl and jq
"
    exit 1
}
while getopts "hy" opt; do
    case ${opt} in
    h) # process option h
        helpmenu
        ;;
    y) # process option y
        INSTALL_MISSING_DEPENDENCIES=yes
        ;;
    \?)
        helpmenu
        exit 1
        ;;
    esac
done

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

if ! hash curl 2>/dev/null && [ ${INSTALL_MISSING_DEPENDENCIES} == "yes" ]; then
    echo '!!!curl was not found!!!'
    echo 'Please install curl if you want to automatically install missing dependencies'
    exit 1
fi
if ! hash kubectl 2>/dev/null; then
    if [ "${INSTALL_MISSING_DEPENDENCIES}" == "yes" ] && [ "${OSTYPE}" == "linux-gnu" ]; then
        curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl
        chmod +x ./kubectl
        mv ./kubectl /bin/kubectl
    else
        echo "!!!kubectl was not found!!!"
        echo "!!!download and install with:"
        echo "Linux users (Run script with option -y to install automatically):"
        echo "curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl"
        echo "chmod +x ./kubectl"
        echo "mv ./kubectl /bin/kubectl"
        exit 1
    fi
fi
if ! hash jq 2>/dev/null; then
    if [ "${INSTALL_MISSING_DEPENDENCIES}" == "yes" ] && [ "${OSTYPE}" == "linux-gnu" ]; then
        curl -L -O https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64
        chmod +x jq-linux64
        mv jq-linux64 /bin/jq
    else
        echo '!!!jq was not found!!!'
        echo "!!!download and install with:"
        echo "Linux users (Run script with option -y to install automatically):"
        echo "curl -L -O https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64"
        echo "chmod +x jq-linux64"
        echo "mv jq-linux64 /bin/jq"
        exit 1
    fi
fi
if ! hash sed 2>/dev/null; then
    echo '!!!sed was not found!!!'
    echo 'Sorry no auto install for this one, please use your package manager.'
    exit 1
fi
if ! hash base64 2>/dev/null; then
    echo '!!!base64 was not found!!!'
    echo 'Sorry no auto install for this one, please use your package manager.'
    exit 1
fi

SSLDIRPREFIX=$(docker inspect kubelet --format '{{ range .Mounts }}{{ if eq .Destination "/etc/kubernetes" }}{{ .Source }}{{ end }}{{ end }}')
if [ "$?" != "0" ]; then
    echo "${green}Failed to get SSL directory prefix, aborting script!${reset}"
    exit 1
fi
function setusupthekubeconfig() {
    kubectl --kubeconfig ${SSLDIRPREFIX}/ssl/kubecfg-kube-node.yaml get configmap -n kube-system full-cluster-state -o json &>/dev/null
    if [ "$?" == "0" ]; then
        echo "${green}Deployed with RKE 0.2.x and newer, grabbing kubeconfig${reset}"
        kubectl --kubeconfig ${SSLDIRPREFIX}/ssl/kubecfg-kube-node.yaml get configmap -n kube-system full-cluster-state -o json | jq -r .data.\"full-cluster-state\" | jq -r .currentState.certificatesBundle.\"kube-admin\".config | sed -e "/^[[:space:]]*server:/ s_:.*_: \"https://127.0.0.1:6443\"_" >${TMPDIR}/kubeconfig
    fi
    kubectl --kubeconfig ${SSLDIRPREFIX}/ssl/kubecfg-kube-node.yaml get secret -n kube-system kube-admin -o jsonpath={.data.Config} &>/dev/null
    if [ "$?" == "0" ]; then
        echo "${green}Deployed with RKE 0.1.x and older, grabbing kubeconfig${reset}"
        kubectl --kubeconfig ${SSLDIRPREFIX}/ssl/kubecfg-kube-node.yaml get secret -n kube-system kube-admin -o jsonpath={.data.Config} | base64 -d | sed 's/[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}/127.0.0.1/g' >${TMPDIR}/kubeconfig
    fi
    if [ ! -f ${TMPDIR}/kubeconfig ]; then
        echo "${red}${TMPDIR}/kubeconfig does not exist, script aborting due to kubeconfig generation failure.${reset} "
        exit 1
    fi
    export KUBECONFIG=${TMPDIR}/kubeconfig
}

echo "${red}Generating kube config for the local cluster${reset}"
setusupthekubeconfig

mkdir -p ~/.kube/
KUBEBACKUP="~/.kube/config-$(date +%Y-%m-%d--%H%M%S)"
FILE="~/.kube/config"
#expand full path
eval FILE=$FILE
eval KUBEBACKUP=$KUBEBACKUP

if [[ -f "$FILE" ]]; then
    echo "${red}Backing up ~/.kube/config to ${KUBEBACKUP}${reset}"
    mv ${FILE} ${KUBEBACKUP}
fi
echo "${red}Copying generated kube config in place${reset}"
cp -afv ${TMPDIR}/kubeconfig ${FILE}
