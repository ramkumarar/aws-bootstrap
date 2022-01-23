#!/bin/bash

STACK_NAME=awsbootstrap
REGION=ap-south-1
CLI_PROFILE=awsbootstrap
EC2_INSTANCE_TYPE=t2.micro
AWS_ACCOUNT_ID=`aws sts get-caller-identity --profile awsbootstrap --query "Account" --output text`
CODEPIPELINE_BUCKET="$STACK_NAME-$REGION-codepipeline-$AWS_ACCOUNT_ID"
CFN_BUCKET="$STACK_NAME-cfn-$AWS_ACCOUNT_ID"

GH_ACCESS_TOKEN=$(cat ~/.github/aws-bootstrap-access-token)
GH_OWNER=$(cat ~/.github/aws-bootstrap-owner)
GH_REPO=$(cat ~/.github/aws-bootstrap-repo)
GH_BRANCH=master
DOMAIN=learncloud.ga
CERT_DOMAIN=*.learncloud.ga

CERT=`aws acm list-certificates --region $REGION --profile awsbootstrap --output text --query "CertificateSummaryList[?DomainName=='$CERT_DOMAIN'].CertificateArn | [0]"`

echo $CERT

# Deploys static resources
aws cloudformation deploy --region $REGION --profile $CLI_PROFILE --stack-name $STACK_NAME-setup --template-file ./setup.yaml --capabilities CAPABILITY_NAMED_IAM --no-fail-on-empty-changeset --parameter-overrides  CodePipelineBucket=$CODEPIPELINE_BUCKET CloudFormationBucket=$CFN_BUCKET

# Package up CloudFormation templates into an S3 bucket
echo -e "\n\n=========== Packaging main.yml ==========="
mkdir -p ./cfn_output

PACKAGE_ERR="$(aws cloudformation package \
  --region $REGION \
  --profile $CLI_PROFILE \
  --template-file ./main.yaml \
  --s3-bucket $CFN_BUCKET \
  --output-template-file ./cfn_output/main.yaml 2>&1 )" 


#PACKAGE_ERR="$(aws cloudformation package --region $REGION --profile $CLI_PROFILE --template-file ./main.yaml --s3-bucket $CFN_BUCKET --output-template-file ./cfn_output/main.yaml 2>&1)"

if ! [[ $PACKAGE_ERR =~ "Successfully packaged artifacts" ]]; then
	echo "ERROR while running 'aws cloudformation package' command:"
	echo $PACKAGE_ERR
	exit 1
fi


# Deploy the CloudFormation template
echo -e "\n\n=========== Deploying main.yml ==========="

aws cloudformation deploy --region $REGION --profile $CLI_PROFILE --stack-name $STACK_NAME --template-file ./cfn_output/main.yaml  --capabilities CAPABILITY_NAMED_IAM --no-fail-on-empty-changeset --parameter-overrides EC2InstanceType=$EC2_INSTANCE_TYPE Domain=$DOMAIN  Certificate=$CERT GitHubBranch=$GH_BRANCH CodePipelineBucket=$CODEPIPELINE_BUCKET GitHubOwner=$GH_OWNER GitHubRepo=$GH_REPO GitHubPersonalAccessToken=$GH_ACCESS_TOKEN


# If the deploy succeeded, show the DNS name of the created instance
if [ $? -eq 0 ]; then
	aws cloudformation list-exports \
		--profile awsbootstrap \
		--query "Exports[?ends_with(Name,'LBEndpoint')].Value"
fi
