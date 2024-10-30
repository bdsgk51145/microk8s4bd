#!/bin/bash
#common
CNC_RN="test"
CNC_NS="cim"
#-----
CNC_VERSION=""
POSTGRES_NAME="postgres"
#-----install-----
function license_setup() {
	#echo -n "Input directory: "
	#read $PF
	#cp $PF ./temp
	pushd ./work
	if [ -f ./license.dat ]; then
		microk8s kubectl create secret generic license-secret --namespace ${CNC_NS} --from-file=license.dat 
	else
		echo "license.dat is not found."
	fi
	popd
}

function repo_setup_and_version_check() {
	if [ -z "$CNC_VERSION" ]; then
		microk8s helm repo list -o yaml | grep bds_repo &> /dev/null
		if [ $? != "0" ]; then
			microk8s helm3 repo add bds_repo https://sig-repo.synopsys.com/artifactory/sig-cloudnative/
		else
			echo "Version Check fail"
                fi
		export CNC_VERSION=$(microk8s helm3 search repo cnc -ojson | jq '.[] | .version' | awk '{print substr($0, 2, length($0)-2)}')
	fi
}


function registry_setup() {
	#echo -n "Input username: "
	#read REGISTRY_USER
	#echo -n "Input Access-Token: "
	#read REGISTRY_PASSWD
	REGISTRY_USER=""
	REGISTRY_PASSWD=""
	CNC_IMAGES=(cim-downloads)
	CNC_IMAGES+=(cim-tools)
	CNC_IMAGES+=(cim-web)
	CNC_IMAGES+=(cov-manage-im)

	#echo ${REGISTRY_PSSSWD} | docker login --username ${REGISTRY_USER} --password-stdin https://${REGISTRY_HOST}
	docker login --username ${REGISTRY_USER} --password ${REGISTRY_PASSWD} https://${REGISTRY_HOST} &> /dev/null
	if [ $? = "0" ]; then
		for n in ${CNC_IMAGES[@]};
		do
			docker pull ${RESISTRY_HOST}/synopsys/$n:${CNC_VERSION}
			docker tag ${REGISTRY_HOST}/synopsys/$n:${CNC_VERSION} localhost:32000/$n:${CNC_VERSION}
			docker push localhost:32000/$n:${CNC_VERSION}
		done
		docker logout ${REGISTRY_HOST}
	else
		echo "login failed test"
	fi
	microk8s kubectl create secret generic registry-secret --from-literal=username=${REGISTRY_USER} --from-literal=password=${REGISTRY_PASSWD} --namespace ${CNC_NS} -o yaml
}

function cnpg_setup() {
#--------------------
cat <<EOF | microk8s kubectl apply -f -
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: ${POSTGRES_NAME}
spec:
  imageName: ghcr.io/cloudnative-pg/postgresql:15.6
  instances: 3
  storage:
    size: 1Gi
EOF
#--------------------
	echo "waiting 120 seconds for create database."
	sleep 120
	POSTGRES_HOST=$(microk8s kubectl get secret ${POSTGRES_NAME}-app -o jsonpath='{.data.host}' | base64 --decode)
	POSTGRES_PORT=$(microk8s kubectl get secret ${POSTGRES_NAME}-app -o jsonpath='{.data.port}' | base64 --decode)
	POSTGRES_USERNAME=$(microk8s kubectl get secret ${POSTGRES_NAME}-app -o jsonpath='{.data.username}' | base64 --decode)
	POSTGRES_PASSWORD=$(microk8s kubectl get secret ${POSTGRES_NAME}-app -o jsonpath='{.data.password}' | base64 --decode)
	microk8s kubectl create secret generic ${POSTGRES_NAME}-secret \
		--from-literal=host=${POSTGRES_HOST} \
		--from-literal=port=${POSTGRES_PORT} \
		--from-literal=user=${POSTGRES_USERNAME} \
		--from-literal=password=${POSTGRES_PASSWORD} \
		-o yaml 
}

function cim_install() {
        microk8s helm3 status ${CNC_RN} --namespace ${CNC_NS} &> /dev/null
        if [ $? != "0" ]; then
		microk8s kubectl get ns ${CNC_NS} &> /dev/null
		if [ $? != "0" ]; then
			microk8s kubectl create ns ${CNC_NS}
		fi
		if [ ! -f ./work/cnc-${CNC_VERSION}.tgz ]; then
			repo_setup_and_version_check
			pushd ./work
			microk8s helm3 pull bds_repo/cnc --version=${CNC_VERSION}
			popd
		fi
		microk8s kubectl get secret license-secret --namespace ${CNC_NS} &> /dev/null
                if [ $? != "0" ]; then
                        license_setup
                fi
		microk8s kubectl get secret registry-secret --namespace ${CNC_NS} &> /dev/null
                if [ $? != "0" ]; then
                        registry_setup
                fi
		microk8s kubectl get secret ${POSTGRES_NAME}-secret &> /dev/null
		#microk8s kubectl get cluster ${POSTGRES_NAME} &> /dev/null
                if [ $? != "0" ]; then
                        cnpg_setup
                fi

		POSTGRES_HOST=$(microk8s kubectl get secret ${POSTGRES_NAME}-app -o=jsonpath='{.data.host}' | base64 --decode)
		POSTGRES_HOST=$(microk8s kubectl get svc ${POSTGRES_HOST} -o=jsonpath='{.spec.clusterIP}')
		POSTGRES_PORT=$(microk8s kubectl get secret ${POSTGRES_NAME}-app -o=jsonpath='{.data.port}' | base64 --decode)
		POSTGRES_USERNAME=$(microk8s kubectl get secret ${POSTGRES_NAME}-app -o=jsonpath='{.data.username}' | base64 --decode)
		POSTGRES_PASSWORD=$(microk8s kubectl get secret ${POSTGRES_NAME}-app -o=jsonpath='{.data.password}' | base64 --decode)
		POSTGRES_DATABASE=$(microk8s kubectl get secret ${POSTGRES_NAME}-app -o=jsonpath='{.data.dbname}' | base64 --decode)

		pushd ./work &> /dev/null
		microk8s helm3 install ${CNC_RN} ./cnc-${CNC_VERSION}.tgz --version ${CNC_VERSION} --namespace=${CNC_NS} \
			--set global.imageVersion=${CNC_VERSION} \
			--set global.imagePullSecret="registry-secret" \
			--set global.imageRegistry="localhost:32000" \
			--set global.licenseSecretName="license-secret" \
			--set cim.postgres.host=${POSTGRES_HOST} \
			--set cim.postgres.port=${POSTGRES_PORT} \
			--set cim.postgres.user=${POSTGRES_USERNAME} \
			--set cim.postgres.password=${POSTGRES_PASSWORD} \
			--set cim.postgres.database=${POSTGRES_DATABASE} \
			--set cim.postgres.sslmode="disable" \
			--set cim.cimweb.webUrl="http://coverity.bdsgk.local" \
			--set cim.cimweb.updateLicense.enabled="true" \
			--set cim.cimweb.updateLicense.force="true" \
			--set cim.cimweb.exposeCommitPort="true" \
			--set cim.cimweb.replicas=1 \
			--set scan-services.enabled=false

		if [ $? = "0" ]; then
			CIM_POD=$(microk8s kubectl get pod -n ${CNC_NS} -oname | awk '{if($1 !~ "cim-setup")print}')
			microk8s kubectl expose $CIM_POD --external-ip=192.168.11.103 --type=LoadBalancer --name=${CNC_RN}-cim-exposed --namespace ${CNC_NS}
		fi
		popd
	else
		echo "Already installed"		
        fi
}
function reset_passwd() {
	microk8s kubectl scale statefulsets ${CNC_RN}-cim-tools --namespace ${CNC_NS} --replicas=1
	sleep 3
	#microk8s kubectl exec -it statefulset/${CNC_RN}-cim-tools --namespace ${CNC_NS} -- /bin/bash
	microk8s kubectl exec -it statefulset/${CNC_RN}-cim-tools --namespace ${CNC_NS} -- ./reset-admin-password.sh
	microk8s kubectl scale statefulsets ${CNC_RN}-cim-tools --namespace ${CNC_NS} --replicas=0
}
#-----upgrade-----
function cim_upgrade() {
	microk8s helm3 status ${CNC_RN} --namespace ${CNC_NS} &> /dev/null
	if [ $? = "0" ]; then
		pushd ./work
		CNC_VERSION=$(microk8s helm3 search repo cnc -ojson | jq '.[] | .version' | awk '{print substr($0, 2, length($0)-2)}')
		CNC_CURRENT_VERSION=$(microk8s helm3 status ${CNC_RN} -n ${CNC_NS} -o json | jq '.config.global.imageVersion' | awk '{print substr($0, 2, length($0)-2)}')
		if [ "$CNC_VERSION" != "$CNC_CURRENT_VERSION" ]; then
			registry_setup
			microk8s helm3 repo update bds_repo https://sig-repo.synopsys.com/artifactory/sig-cloudnative/
			microk8s helm3 pull bds_repo/cnc
			rm cnc-${CNC_CURRENT_VERSION}.tgz
		fi
		microk8s helm3 upgrade ${CNC_RN} bds_repo/cnc --namespace ${CNC_NS} --reuse-values
		popd
	else
		echo "Not found ${CNC_RN}"
	fi
}

#-----uninstall-----
function cim_uninstall() {
	microk8s helm3 status ${CNC_RN} --namespace ${CNC_NS} &> /dev/null
	if [ $? = "0" ]; then
		pushd ./work
		microk8s helm3 uninstall ${CNC_RN} --namespace ${CNC_NS}
		microk8s kubectl delete svc ${CNC_RN}-cim-exposed --namespace ${CNC_NS}
		#microk8s kubectl delete secret ${POSTGRES_NAME}-secret
		#microk8s kubectl delete cluster ${POSTGRES_NAME}
		#microk8s kubectl delete secret license-secret --namespace ${CNC_NS}
		#microk8s kubectl delete secret registry-secret --namespace ${CNC_NS}
		popd
	else
		echo "Not found ${CNC_RN}"
	fi
}
#-----clean-----
function cim_clean() {
	pushd ./work
	#CNC_CURRENT_VERSION=$(microk8s helm3 status ${CNC_RN} -n ${CNC_NS} -o json | jq '.config.global.imageVersion' | awk '{print substr($0, 2, length($0)-2)}')
	rm cnc-*.tgz
	rm license.dat
	popd
	cim_uninstall

	microk8s kubectl delete secret ${POSTGRES_NAME}-secret
	microk8s kubectl delete cluster ${POSTGRES_NAME}
	microk8s kubectl delete secret license-secret --namespace ${CNC_NS}
	microk8s kubectl delete secret registry-secret --namespace ${CNC_NS}
	microk8s kubectl delete ns ${CNC_NS}
	microk8s helm3 repo remove bds_repo
}

if [ "$1" = "install" ]; then
	cim_install
elif [ "$1" = "reset_password" ]; then
	reset_passwd
elif [ "$1" = "upgrade" ]; then
	cim_upgrade
elif [ "$1" = "uninstall" ]; then
	cim_uninstall
elif [ "$1" = "clean" ]; then
	cim_clean
else
	echo "Usage: ./cim-ctrl.sh [install/reset_password/upgrade/uninstall]"
fi

