#!/bin/bash
#common
SKR_RN="test"
SKR_NS="seeker"

#-----install-----
function registry_setup() {
	IBH_USERNAME=""
	IBH_PASSWORD=""

	#echo "Require IRON BANK account"
	#echo -n "Username: "	
	#read IBH_USERNAME
	#echo -n "Password: "
	#read IBH_PASSWORD

	IBH_USERNAME="masao"
	IBH_PASSWORD="wa09I0Bv6se9nT6XJC0Kgg3Ei2gthjQC"
	microk8s kubectl create secret docker-registry ${SKR_RN}-seeker-register-secret --docker-server=registry1.dso.mil --docker-username=$IBH_USERNAME --docker-password=$IBH_PASSWORD --namespace ${SKR_NS}
}
function db_setup() {
	PASSPHRASE=$(echo -n "test-seeker-db-passphrase" | base64)
#--------------------
cat <<EOF | microk8s kubectl apply -f -
apiVersion: v1
kind: Secret
metadata: 
  name: ${SKR_RN}-seeker-db-secret
  namespace: ${SKR_NS}	
type: Opaque
data:
  dbpass: $PASSPHRASE
EOF
#--------------------
}
function skr_install() {
	microk8s helm3 status ${SKR_RN} --namespace ${SKR_NS} &> /dev/null
	if [ $? != "0" ]; then
		pushd ./work &> /dev/null
		if [ ! -d ./seeker-k8s ]; then
			git clone https://github.com/synopsys-sig/seeker-k8s
		fi
		popd &> /dev/null
		microk8s kubectl get ns ${SKR_NS} &> /dev/null &> /dev/null
		if [ $? != "0" ]; then
			microk8s kubectl create ns ${SKR_NS}
		fi
		microk8s kubectl get secret ${SKR_RN}-seeker-register-secret --namespace ${SKR_NS} &> /dev/null
		if [ $? != "0" ]; then
			registry_setup
		fi
		microk8s kubectl get secret ${SKR_RN}-seeker-db-secret --namespace ${SKR_NS} &> /dev/null
		if [ $? != "0" ]; then
			db_setup
		fi
		pushd ./work/seeker-k8s
		microk8s helm3 install ${SKR_RN} ./seeker --namespace ${SKR_NS} \
			--set imagePullSecrets=${SKR_RN}-seeker-register-secret \
			--set externalDatabasePasswordSecret=${SKR_RN}-seeker-db-secret
		popd
		SKR_EXPOSE=$(microk8s kubectl get pod -n ${SKR_NS} -oname | awk '{if($1 ~ "nginx")print}')
		microk8s kubectl expose $SKR_EXPOSE --external-ip=192.168.11.104 --port=8080 --target-port=8080 --type=LoadBalancer --name=${SKR_RN}-seeker-nginx-exposed --namespace ${SKR_NS}
	else
		echo "Already installed"
	fi
}

#-----upgrade-----
function skr_upgrade() {
	microk8s helm3 status ${SKR_RN} --namespace ${SKR_NS} &> /dev/null
	if [ $? = "0" ]; then
		pushd ./work &> /dev/null
		#if [ -d ./seeker-k8s ]; then
			git clone https://github.com/synopsys-sig/seeker-k8s
		#fi
		popd &> /dev/null
		pushd ./work/seeker-k8s &> /dev/null
		microk8s helm3 upgrade ${SKR_RN} ./seeker --namespace ${SKR_NS} --reuse-values
		popd &> /dev/null
	else
		echo "Not found ${SKR_RN}"
	fi
}

#-----uninstall-----
function skr_uninstall() {
	microk8s kubectl delete service ${SKR_RN}-seeker-nginx-exposed --namespace ${SKR_NS}
	microk8s helm3 status ${SKR_RN} --namespace ${SKR_NS} &> /dev/null
	if [ $? = "0" ]; then
		#microk8s kubectl delete service ${SRM_RN}-srm-web-exposed --namespace ${SRM_NS}
		microk8s helm3 uninstall ${SKR_RN} --namespace ${SKR_NS}
	else
		echo "Not found ${SKR_RN}"
	fi
}
#-----clean-----
function skr_clean() {
	skr_uninstall
	microk8s kubectl delete secret ${SKR_RN}-seeker-db-secret --namespace ${SKR_NS}
	microk8s kubectl delete secret ${SKR_RN}-seeker-register-secret --namespace ${SKR_NS}
	microk8s kubectl delete ns ${SKR_NS}
	pushd ./work
		rm -rf ./seeker-k8s
	popd
}

if [ "$1" = "install" ]; then
	skr_install
elif [ "$1" = "upgrade" ]; then
	skr_upgrade
elif [ "$1" = "uninstall" ]; then
	skr_uninstall
elif [ "$1" = "clean" ]; then
	skr_clean
else
	echo "Usage: ./seeker-microk8s.sh [install/upgrade/uninstall]"
fi

