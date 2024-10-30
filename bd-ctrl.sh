#!/bin/bash
#common
BD_RN="test"
BD_NS="bd"

#-----install-----
function bd_install() {
	microk8s helm3 status ${BD_RN} --namespace ${BD_NS} &> /dev/null
	if [ $? != "0" ]; then
		microk8s helm3 repo list -o yaml | grep bds_repo &> /dev/null
		if [ $? != "0" ] ; then
			microk8s helm3 repo add bds_repo https://sig-repo.synopsys.com/artifactory/sig-cloudnative 1> /dev/null
		fi
		microk8s kubectl get ns ${BD_NS} &> /dev/null
		if [ $? != "0" ]; then
			microk8s kubectl create ns ${BD_NS}
		fi

		microk8s helm3 install ${BD_RN} bds_repo/blackduck --namespace ${BD_NS} \
			--set postgres.isExternal=false \
			--set storageClass=microk8s-hostpath
		microk8s kubectl delete service ${BD_RN}-blackduck-webserver-exposed --namespace ${BD_NS}
		BLACKDUCK_EXPOSE=$(microk8s kubectl get pod -n ${BD_NS} -oname | awk '{if($1 ~ "blackduck-webserver")print}')
		microk8s kubectl expose $BLACKDUCK_EXPOSE --external-ip=192.168.11.102 --port=443 --target-port=8443 --type=LoadBalancer --name=${BD_RN}-blackduck-webserver-exposed --namespace ${BD_NS}
	else
		echo "Already installed"
	fi
}

#-----upgrade-----
function bd_upgrade() {
	microk8s helm3 status ${BD_RN} --namespace ${BD_NS} &> /dev/null
	if [ $? = "0" ]; then
		microk8s helm3 repo update bds_repo
		microk8s helm3 upgrade ${BD_RN} bds_repo/blackduck --namespace ${BD_NS} --reuse-values
		microk8s kubectl delete service ${BD_RN}-blackduck-webserver-exposed --namespace ${BD_NS}
		BLACKDUCK_EXPOSE=$(microk8s kubectl get pod -n ${BD_NS} -oname | awk '{if($1 ~ "blackduck-webserver")print}')
		microk8s kubectl expose $BLACKDUCK_EXPOSE --external-ip=192.168.11.102 --port=443 --target-port=8443 --type=LoadBalancer --name=${BD_RN}-blackduck-webserver-exposed --namespace ${BD_NS}
	else
		echo "Not found ${BD_RN}"
	fi
}

#-----uninstall-----
function bd_uninstall() {
	microk8s helm3 status ${BD_RN} --namespace ${BD_NS} &> /dev/null
	if [ $? = "0" ]; then
		microk8s helm3 uninstall ${BD_RN} --namespace ${BD_NS}
		microk8s kubectl delete secret ${BD_RN}-blackduck-db-creds -n ${BD_NS} 2> /dev/null
		microk8s kubectl delete configmap ${BD_RN}-blackduck-db-config -n ${BD_NS} 2> /dev/null
	else
		echo "Not found ${BD_RN}"
	fi
}
#-----clean-----
function bd_clean() {
	bd_uninstall
	microk8s kubectl delete ns ${BD_NS}
	microk8s helm3 repo remove bds_repo
}

if [ "$1" = "install" ]; then
	bd_install
elif [ "$1" = "upgrade" ]; then
	bd_upgrade
elif [ "$1" = "uninstall" ]; then
	bd_uninstall
elif [ "$1" = "clean" ]; then
	bd_clean
else
	echo "Usage: ./bd-microk8s.sh [install/upgrade/uninstall]"
fi

