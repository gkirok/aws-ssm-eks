#!/bin/sh

if [ -n "${AWS_ACCESS_KEY_ID:-}" ]; then
  export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}"
fi

if [ -n "${AWS_SECRET_ACCESS_KEY:-}" ]; then
  export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}"
fi

if [ -n "${AWS_REGION:-}" ]; then
  export AWS_DEFAULT_REGION="${AWS_REGION}"
fi

echo "aws version"
aws --version

echo "Attempting to update kubeconfig for aws"
aws eks update-kubeconfig --name "${CLUSTER_NAME}"

if [ -n "${BASTION_NAME}" ]; then
  echo "Bastion: $BASTION_NAME";
  export INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=${BASTION_NAME}" "Name=instance-state-code,Values=16" --output text --query 'Reservations[*].Instances[*].InstanceId')
elif [ -n "${BASTION_ID}" ]; then
  export INSTANCE_ID=$BASTION_ID
else
  echo "Required: BASTION_NAME or BASTION_ID"
  exit 1
fi
echo "InstanceId: $INSTANCE_ID";

CLUSTER_API=$(aws eks describe-cluster --name $CLUSTER_NAME | jq -r '.cluster.endpoint' | awk -F/ '{print $3}')
echo "Cluster API: $CLUSTER_API";

if [ -n "${SSM_PORT:-}" ]; then
  PORT=$SSM_PORT
else
  PORT="$((8 + $RANDOM % 25))443"
fi
echo "Port: $PORT"

echo "Update /etc/hosts"
sh -c "echo '127.0.0.1 ${CLUSTER_API}' >> /etc/hosts"

echo "Update ~/.kube/config"
sed -i -e "s/https:\/\/$CLUSTER_API/https:\/\/$CLUSTER_API:$PORT/" ~/.kube/config

echo "Starting session"
output=$( nohup aws ssm start-session --target ${INSTANCE_ID} --document-name AWS-StartPortForwardingSessionToRemoteHost --parameters "{\"host\": [ \"${CLUSTER_API}\" ], \"portNumber\": [ \"443\" ], \"localPortNumber\": [ \"$PORT\" ] }" & )
echo "${output}"
sleep 10
echo ::set-output name=ssm-out::"${output}"