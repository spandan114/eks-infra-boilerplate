#!/bin/bash

# Exit on error
set -e

echo "Creating EKS cluster..."

# Create the EKS cluster using eksctl
eksctl create cluster -f eks-cluster.yaml

echo "EKS cluster created successfully!"

# Get the VPC ID
VPC_ID=$(aws eks describe-cluster --name my-eks-cluster --region ap-south-1 --query "cluster.resourcesVpcConfig.vpcId" --output text)
echo "VPC ID: $VPC_ID"

# Setup AWS Load Balancer Controller
echo "Setting up AWS Load Balancer Controller..."

# Create IAM OIDC provider for the cluster
eksctl utils associate-iam-oidc-provider --cluster my-eks-cluster --region ap-south-1 --approve

# Create IAM policy for the AWS Load Balancer Controller
echo "Creating IAM policy for AWS Load Balancer Controller..."
curl -o iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.4.7/docs/install/iam_policy.json

aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json

# Create service account for the AWS Load Balancer Controller
eksctl create iamserviceaccount \
  --cluster=my-eks-cluster \
  --region=ap-south-1 \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn=arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/AWSLoadBalancerControllerIAMPolicy \
  --override-existing-serviceaccounts \
  --approve

# Install the AWS Load Balancer Controller using Helm
echo "Installing Helm..."
curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash

# Apply CRDs first
echo "Applying AWS Load Balancer Controller CRDs..."
kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller/crds?ref=master"

echo "Installing AWS Load Balancer Controller..."
# Add the EKS chart repo
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Use a more reliable approach for installing the controller
kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller/crds?ref=master"

# Install the controller using a more explicit approach
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=my-eks-cluster \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=ap-south-1 \
  --set vpcId=$VPC_ID \
  --version 1.4.8

# Verify the controller is running
echo "Verifying the AWS Load Balancer Controller installation..."
kubectl -n kube-system wait --for=condition=available --timeout=90s deployment/aws-load-balancer-controller

# Wait for webhook to become available
echo "Waiting for webhook service to be ready..."
sleep 15
kubectl -n kube-system get svc aws-load-balancer-webhook-service

echo "Done! EKS cluster is ready for deployments."
echo "To update your kubeconfig, run:"
echo "aws eks update-kubeconfig --name my-eks-cluster --region ap-south-1" 