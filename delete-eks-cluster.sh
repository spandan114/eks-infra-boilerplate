#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

CLUSTER_NAME="my-eks-cluster"
REGION="ap-south-1"

echo "🧹 Starting cleanup process for EKS cluster: $CLUSTER_NAME in region: $REGION"

# Check if cluster exists
echo "Checking if cluster exists..."
if ! aws eks describe-cluster --name $CLUSTER_NAME --region $REGION &>/dev/null; then
  echo "Cluster $CLUSTER_NAME does not exist in region $REGION. Nothing to delete."
  exit 0
fi

# Configure kubectl 
echo "Updating kubeconfig for cluster $CLUSTER_NAME..."
aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION

# Step 1: Delete any LoadBalancer services to ensure proper cleanup of AWS resources
echo "Step 1: Deleting Kubernetes LoadBalancer services..."
if kubectl get ingress &>/dev/null; then
  echo "Deleting ingress resources..."
  kubectl delete ingress --all
  echo "Waiting for 30 seconds to ensure load balancers are deleted..."
  sleep 30
fi

# Step 2: Delete the AWS Load Balancer Controller
echo "Step 2: Deleting AWS Load Balancer Controller..."
if helm list -n kube-system | grep aws-load-balancer-controller &>/dev/null; then
  helm uninstall aws-load-balancer-controller -n kube-system
  echo "AWS Load Balancer Controller deleted."
  
  # Delete the CRDs
  echo "Deleting AWS Load Balancer Controller CRDs..."
  kubectl delete -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller/crds?ref=master" || true
  echo "CRDs deleted or already removed."
fi

# Step 3: Delete the IAM service account
echo "Step 3: Deleting IAM service account..."
eksctl delete iamserviceaccount \
  --cluster=$CLUSTER_NAME \
  --region=$REGION \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  || echo "IAM service account deletion skipped."

# Step 4: Delete IAM policy (this is a best effort, it might fail if it's used by other resources)
echo "Step 4: Deleting IAM policy..."
POLICY_ARN=$(aws iam list-policies --query "Policies[?PolicyName=='AWSLoadBalancerControllerIAMPolicy'].Arn" --output text)
if [ ! -z "$POLICY_ARN" ]; then
  aws iam delete-policy --policy-arn $POLICY_ARN || echo "Failed to delete IAM policy (it might be in use)"
fi

# Step 5: Delete the EKS cluster
echo "Step 5: Deleting EKS cluster: $CLUSTER_NAME..."
echo "⚠️  This will delete the entire EKS cluster and all its resources! ⚠️"
echo "You have 10 seconds to press Ctrl+C to abort..."
sleep 10
echo "Proceeding with cluster deletion..."

eksctl delete cluster --name $CLUSTER_NAME --region $REGION --wait

# Step 6: Clean up ECR repositories (optional)
echo "Step 6: Do you want to delete ECR repositories for user-service and workflow-service? (y/n)"
read -r answer
if [[ "$answer" == "y" ]]; then
  echo "Deleting ECR repositories..."
  aws ecr delete-repository --repository-name user-service --region $REGION --force || echo "Failed to delete user-service repository (it might not exist)"
  aws ecr delete-repository --repository-name workflow-service --region $REGION --force || echo "Failed to delete workflow-service repository (it might not exist)"
  echo "ECR repositories deleted."
else
  echo "Skipping ECR repository deletion."
fi

# Clean up any temporary files
if [ -f "iam_policy.json" ]; then
  rm iam_policy.json
  echo "Removed temporary IAM policy file."
fi

echo "🎉 Cleanup complete! The EKS cluster and related resources have been deleted." 