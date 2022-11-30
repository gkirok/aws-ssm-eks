#!/bin/bash
set -x
PORT=''
refused=0
rand_port(){
  if [ -n "${SSM_PORT:-}" ]; then
    PORT=$SSM_PORT
  else
    PORT="20$((570 + $RANDOM % 429))"
  fi
  echo "::debug::Port: $PORT"
}
echo "::group::aws-ssm-eks init"
if [ -n "${AWS_ACCESS_KEY_ID:-}" ]; then
  export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}"
fi

if [ -n "${AWS_SECRET_ACCESS_KEY:-}" ]; then
  export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}"
fi

if [ -n "${AWS_REGION:-}" ]; then
  export AWS_DEFAULT_REGION="${AWS_REGION}"
fi

echo "::debug::aws version"
echo "::debug::$(aws --version)"

echo "::notice::Attempting to update kubeconfig for aws"
echo "$CLUSTER_NAME"

if [ -n "${BASTION_NAME}" ]; then
  echo "::debug::Bastion: $BASTION_NAME"
  INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=${BASTION_NAME}" "Name=instance-state-code,Values=16" --output text --query 'Reservations[*].Instances[*].InstanceId')
  export INSTANCE_ID
elif [ -n "${BASTION_ID}" ]; then
  export INSTANCE_ID=$BASTION_ID
else
  echo "::error::Required: BASTION_NAME or BASTION_ID"
  exit 1
fi
echo "::debug::InstanceId: $INSTANCE_ID"

CLUSTER=$(aws eks describe-cluster --name "$CLUSTER_NAME" 2>/tmp/stderr)
ret=$?
if [ $ret -ne 0 ]; then
  echo "::error::Error: aws eks describe-cluster"
  cat /tmp/stderr
  exit $ret
fi
CLUSTER_API=$(echo "${CLUSTER}" | jq -r '.cluster.endpoint' | awk -F/ '{print $3}')
echo "::debug::Cluster API: $CLUSTER_API"

echo "::notice::Update /etc/hosts"
sh -c "echo '127.0.0.1 ${CLUSTER_API}' >> /etc/hosts"
echo "::endgroup::"
echo "::group::aws-ssm-eks"
rand_port
echo $PORT

EKS_NAME=$(aws eks update-kubeconfig --name "${CLUSTER_NAME}" 2>/tmp/stderr)
ret=$?
if [ $ret -ne 0 ]; then
  echo "::error::Error: aws eks update-kubeconfig"
  cat /tmp/stderr
  exit $ret
fi

echo "::notice::Update ~/.kube/config"
sed -i -e "s/https:\/\/$CLUSTER_API/https:\/\/$CLUSTER_API:$PORT/" ~/.kube/config

echo "::notice::Starting session"
aws ssm start-session --target ${INSTANCE_ID} --document-name AWS-StartPortForwardingSessionToRemoteHost --parameters "{\"host\": [ \"${CLUSTER_API}\" ], \"portNumber\": [ \"443\" ], \"localPortNumber\": [ \"$PORT\" ] }" &
sleep 10

echo "::notice::Get session id"
MY_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
SESSION_ID=$(aws ssm describe-sessions --state "Active" \
  --filters "key=Owner,value=$MY_IDENTITY" "key=Target,value=$INSTANCE_ID" "key=Status,value=Connected" \
  --query 'Sessions[].{SessionId:SessionId,StartDate:StartDate} | reverse(sort_by(@, &StartDate)) | [0].SessionId' --output text)
sleep 3

if [ -n "${run}" ]; then
  echo "::notice::Running bash commands"
  echo "$run" >>/tmp/run_cmds.sh
  cat /tmp/run_cmds.sh
  bash /tmp/run_cmds.sh 2>/tmp/stderr
  ret=$?
  echo "::debug::bash cmds ret: $ret"
else
  echo "::error::Empty commands"
  exit 1
fi

if [ $ret -ne 0 ]; then
  echo "::error::Error executing commands"
  cat /tmp/stderr
  exit 1
fi

if [ $ret -eq 0 ]; then
  echo "::notice::Finished Successfully"
  exit 0
else
  echo "::error::Finished with errors"
  exit 1
fi
