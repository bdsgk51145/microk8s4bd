#!/bin/bash
BD_NAME="bd"

# delete chart
helm delete ${BD_NAME} --namespace ${BD_NAME}
# kubectl delete configmap --namespace ${BD_NAME} ${BD_NAME}-blackduck-postgres-init-config
kubectl delete configmap --namespace ${BD_NAME} ${BD_NAME}-blackduck-db-config
kubectl delete secret --namespace ${BD_NAME} ${BD_NAME}-blackduck-db-creds

# delete pvc
kubectl delete pvc --all --namespace ${BD_NAME}

# delete pv
count=0
while true
do
        kubectl delete pv local-pv$[count++]
        if [ $count -eq 10 ]; then
                exit 0
        fi
done

#--- Ref: ---
# https://github.com/blackducksoftware/hub/blob/master/kubernetes/blackduck/README.md
