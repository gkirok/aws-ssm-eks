#!/bin/sh

if [ -n "${INPUT_AWS_ACCESS_KEY_ID:-}" ]; then
  export AWS_ACCESS_KEY_ID="${INPUT_AWS_ACCESS_KEY_ID}"
fi

if [ -n "${INPUT_AWS_SECRET_ACCESS_KEY:-}" ]; then
  export AWS_SECRET_ACCESS_KEY="${INPUT_AWS_SECRET_ACCESS_KEY}"
fi

if [ -n "${INPUT_AWS_REGION:-}" ]; then
  export AWS_DEFAULT_REGION="${INPUT_AWS_REGION}"
fi

echo "aws version"

aws --version

echo "Attempting to update kubeconfig for aws"

if [ -n "${INPUT_EKS_ROLE_ARN}" ]; then
  aws eks update-kubeconfig --name "${INPUT_CLUSTER_NAME}" --role-arn "${INPUT_EKS_ROLE_ARN}"
else
  aws eks update-kubeconfig --name "${INPUT_CLUSTER_NAME}"
fi

echo "Cluster: $INPUT_CLUSTER_NAME";
echo "Bastion name: $INPUT_BASTION_NAME";
echo "Bastion id: $INPUT_BASTION_ID";
echo "Bastion name: $BASTION_NAME";
echo "Bastion id: $BASTION_ID";

if [ -n "${INPUT_BASTION_NAME}" ]; then
  echo "Bastion: $INPUT_BASTION_NAME";
  export INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=${INPUT_BASTION_NAME}" "Name=instance-state-code,Values=16" --output text --query 'Reservations[*].Instances[*].InstanceId')
elif [ -n "${INPUT_BASTION_ID}" ]; then
  export INSTANCE_ID=$INPUT_BASTION_ID
else
  echo "Required: BASTION_NAME or BASTION_ID"
  exit 1
fi
echo "InstanceId: $INSTANCE_ID";

CLUSTER_API=$(aws eks describe-cluster --name $INPUT_CLUSTER_NAME | jq -r '.cluster.endpoint' | awk -F/ '{print $3}')
echo "Cluster API: $CLUSTER_API";

if [ -n "${INPUT_SSM_PORT:-}" ]; then
  PORT=$INPUT_SSM_PORT
else
  PORT="$((8 + $RANDOM % 25))443"
fi
echo "Port: $PORT"

echo "Update /etc/hosts"
sudo sh -c "echo '127.0.0.1 ${CLUSTER_API}' >> /etc/hosts"

echo "Update ~/.kube/config"
sed -i -e "s/https:\/\/$CLUSTER_API/https:\/\/$CLUSTER_API:$PORT/" ~/.kube/config

CLUSTER_ARN=$(aws eks describe-cluster --name $INPUT_CLUSTER_NAME | jq -r '.cluster.arn')
echo "Cluster ARN: $CLUSTER_ARN"
kubectl config use-context $CLUSTER_ARN

echo "Starting session"
output=$( nohup aws ssm start-session --target ${INSTANCE_ID} --document-name AWS-StartPortForwardingSessionToRemoteHost --parameters "{\"host\": [ \"${CLUSTER_API}\" ], \"portNumber\": [ \"443\" ], \"localPortNumber\": [ \"$PORT\" ] }" & )
echo "${output}"
sleep 10
echo ::set-output name=ssm-out::"${output}"
