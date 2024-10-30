#!/bin/bash
#common
SRM_RN="test"
SRM_NS="srm"

#-----install-----
function srm_install() {
	microk8s helm3 status ${SRM_RN} --namespace ${SRM_NS} &> /dev/null
	if [ $? != "0" ]; then
		pushd ./work &> /dev/null
		if [ ! -d ./srm-k8s ]; then
			git clone https://github.com/synopsys-sig/srm-k8s
			microk8s kubectl apply -f srm-k8s/crds/v1
		fi
		popd &> /dev/null
		microk8s helm3 repo list -o yaml | grep srm_repo &> /dev/null
		if [ $? != "0" ] ; then
			microk8s helm3 repo add srm_repo https://synopsys-sig.github.io/srm-k8s 1> /dev/null
		fi
		microk8s kubectl get ns ${SRM_NS} &> /dev/null
		if [ $? != "0" ]; then
			microk8s kubectl create ns ${SRM_NS}
		fi

		microk8s helm3 install ${SRM_RN} srm_repo/srm --namespace ${SRM_NS}

		SRM_EXPOSE=$(microk8s kubectl get pod -n ${SRM_NS} -oname | awk '{if($1 ~ "srm-web")print}')
		#microk8s kubectl expose $SRM_EXPOSED --external-ip=192.168.11.105 --port=80 --target-port=9090 --type=LoadBalancer --name=${SRM_RN}-srm-exposed --namespace ${SRM_NS}
		microk8s kubectl expose $SRM_EXPOSE --external-ip=192.168.11.105 --type=LoadBalancer --name=${SRM_RN}-srm-web-exposed --namespace ${SRM_NS}
	else
		echo "Already installed"
	fi
}
function get_passwd() {
	microk8s kubectl get secret ${SRM_RN}-default-web-secret --namespace ${SRM_NS} -o jsonpath='{.data.admin-password}' | base64 --decode
}
#-----upgrade-----
function srm_upgrade() {
	microk8s helm3 status ${SRM_RN} --namespace ${SRM_NS} &> /dev/null
	if [ $? = "0" ]; then
		pushd ./work
		if [ -d ./srm-k8s ]; then
			git clone https://github.com/synopsys-sig/srm-k8s
			microk8s kubectl apply -f srm-k8s/crds/v1
		fi
		popd
		microk8s helm3 repo update srm_repo
		microk8s helm3 upgrade ${SRM_RN} srm_repo/srm --namespace ${SRM_NS} --reuse-values
	else
		echo "Not found ${SRM_RN}"
	fi
}

#-----uninstall-----
function srm_uninstall() {
	microk8s helm3 status ${SRM_RN} --namespace ${SRM_NS} &> /dev/null
	if [ $? = "0" ]; then
		pushd ./work
		microk8s kubectl delete service ${SRM_RN}-srm-web-exposed --namespace ${SRM_NS}
		microk8s helm3 uninstall ${SRM_RN} --namespace ${SRM_NS}
		microk8s kubectl delete ns ${SRM_NS}
		popd
	else
		echo "Not found ${SRM_RN}"
	fi
}
#-----clean-----
function srm_clean() {
	srm_uninstall
	#microk8s kubectl delete ns ${SRM_NS}
	pushd ./work
		microk8s kubectl delete -f srm-k8s/crds/v1
		rm -rf ./srm-k8s
	popd
	microk8s helm3 repo remove srm_repo
}

if [ "$1" = "install" ]; then
	srm_install
elif [ "$1" = "upgrade" ]; then
	srm_upgrade
elif [ "$1" = "uninstall" ]; then
	srm_uninstall
elif [ "$1" = "clean" ]; then
	srm_clean
else
	echo "Usage: ./srm-microk8s.sh [install/upgrade/uninstall]"
fi

