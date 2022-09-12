#!/bin/sh
echo "::group::aws-ssm-eks"
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

EKS_NAME=$(aws eks update-kubeconfig --name "${CLUSTER_NAME}" 2> /tmp/stderr);
ret=$?
if [ $ret -ne 0 ]; then
  echo "Error: aws eks update-kubeconfig"
  cat /tmp/stderr
  exit $ret
fi

if [ -n "${BASTION_NAME}" ]; then
  echo "::debug::Bastion: $BASTION_NAME";
  export INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=${BASTION_NAME}" "Name=instance-state-code,Values=16" --output text --query 'Reservations[*].Instances[*].InstanceId')
elif [ -n "${BASTION_ID}" ]; then
  export INSTANCE_ID=$BASTION_ID
else
  echo "Required: BASTION_NAME or BASTION_ID"
  exit 1
fi
echo "::debug::InstanceId: $INSTANCE_ID";

CLUSTER=$(aws eks describe-cluster --name $CLUSTER_NAME 2> /tmp/stderr)
ret=$?
if [ $ret -ne 0 ]; then
  echo "Error: aws eks describe-cluster"
  cat /tmp/stderr
  exit $ret
fi
CLUSTER_API=$(echo "${CLUSTER}" | jq -r '.cluster.endpoint' | awk -F/ '{print $3}')
echo "::debug::Cluster API: $CLUSTER_API";

if [ -n "${SSM_PORT:-}" ]; then
  PORT=$SSM_PORT
else
  PORT="20$((570 + $RANDOM % 130))"
fi
echo "::debug::Port: $PORT"

echo "::notice::Update /etc/hosts"
sh -c "echo '127.0.0.1 ${CLUSTER_API}' >> /etc/hosts"

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

# netstat -v

echo "::notice::Running kubectl"
runme="kubectl $kubectl"
output=$( bash -c "$runme" 2> /tmp/stderr)
ret=$?

# echo "${output}"
# ps aux

echo "::notice::Terminate session"
aws ssm terminate-session --session-id $SESSION_ID

if [ $ret -ne 0 ]; then
  echo "Error: kubectl"
  cat /tmp/stderr
  echo ::set-output name=cmd-out::"$(cat /tmp/stderr)"
  exit $ret
fi
echo "::endgroup::"

echo ::set-output name=cmd-out::"${output}"
