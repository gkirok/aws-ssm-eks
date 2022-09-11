# aws-ssm-eks docker action

This action connects to eks with private endpoint using ssm session on bastion server

## Prerequisites

```yaml
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "ssm",
            "Effect": "Allow",
            "Action": [
                "ssm:StartSession",
                "ssm:TerminateSession"
            ],
            "Resource": "*"
        },
        {
            "Sid": "eks",
            "Effect": "Allow",
            "Action": [
                "eks:DescribeCluster",
                "eks:ListClusters"
            ],
            "Resource": "*"
        },
        {
            "Sid": "ec2",
            "Effect": "Allow",
            "Action": [
               "ec2:DescribeInstances",
               "ec2:DescribeTags"
            ],
            "Resource": "*"
       }
    ]
}
```

## Inputs

| Input | Description | Default |
| ----- | ----------- | ------- |
| CLUSTER_NAME | The name of eks cluster. | **Required** |
| BASTION_NAME | The bastion instance name | **Required** or BASTION_ID |
| BASTION_ID | The bastion instance id | **Required** or BASTION_NAME |
| AWS_ACCESS_KEY_ID |  | None |
| AWS_SECRET_ACCESS_KEY |  | None |
| AWS_REGION |  | None |
| SSM_PORT | SSM local port | None |

## Outputs

## `cmd output`

The kubectl command output.

## Example usage
```yaml
  - name: Configure AWS credentials
    uses: aws-actions/configure-aws-credentials@v1
    with:
      aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
      aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
      aws-region: ${{ env.region }}

  - name: Running ssm session
    uses: gkirok/aws-ssm-eks@v1
    env:
      CLUSTER_NAME: my-cluster
      BASTION_NAME: my-bastion

  - name: list pods
    shell: bash
    run: |
      curl -LO "https://dl.k8s.io/release/v1.21.9/bin/linux/amd64/kubectl"
      chmod 700 kubectl
      ./kubectl get pods -A
```
### Set BASTION_ID
```yaml
  - name: Running ssm session
    uses: gkirok/aws-ssm-eks@v1
    env:
      AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
      AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
      AWS_REGION: ${{ secrets.AWS_REGION }}
      CLUSTER_NAME: my-cluster
      BASTION_ID: id-98h3tboagua94gboa
      SSM_PORT: 8443
```
