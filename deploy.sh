#!/bin/bash

# Exit on error
set -e

# Get AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="ap-south-1"

echo "===== Starting full deployment process ====="
echo "Using AWS Account ID: $ACCOUNT_ID"
echo "Using Region: $REGION"

# Check if cluster exists
if ! aws eks describe-cluster --name my-eks-cluster --region $REGION &>/dev/null; then
  echo "⚠️  EKS cluster not found. Creating cluster..."
  ./create-eks-cluster.sh
else
  echo "✅ EKS cluster already exists."
fi

# Build and push Docker images
echo -e "\n===== Building and pushing Docker images ====="

# Log in to ECR
echo "Logging in to Amazon ECR..."
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

# Make sure repositories exist
echo "Ensuring ECR repositories exist..."

# Check and create user service repository if needed
if aws ecr describe-repositories --repository-names user-service --region $REGION &>/dev/null; then
  echo "✅ User service repository already exists"
else
  echo "Creating user service repository..."
  aws ecr create-repository --repository-name user-service --region $REGION
  echo "✅ User service repository created"
fi

# Check and create workflow service repository if needed
if aws ecr describe-repositories --repository-names workflow-service --region $REGION &>/dev/null; then
  echo "✅ Workflow service repository already exists"
else
  echo "Creating workflow service repository..."
  aws ecr create-repository --repository-name workflow-service --region $REGION
  echo "✅ Workflow service repository created"
fi

# Build and push user service
echo "Building and pushing user service..."
cd app/user
docker build --platform=linux/amd64 -t $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/user-service:latest .
docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/user-service:latest
cd ../..

# Build and push workflow service
echo "Building and pushing workflow service..."
cd app/workflow
docker build --platform=linux/amd64 -t $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/workflow-service:latest .
docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/workflow-service:latest
cd ../..

echo "✅ Images built and pushed successfully!"

# Deploy to Kubernetes
echo -e "\n===== Deploying to Kubernetes ====="

# Apply user service
echo "Applying user-service deployment..."
cat k8s/user-deployment.yaml | sed "s/ACCOUNT_ID/$ACCOUNT_ID/g" | sed "s/REGION/$REGION/g" | kubectl apply -f -

# Apply workflow service
echo "Applying workflow-service deployment..."
cat k8s/workflow-deployment.yaml | sed "s/ACCOUNT_ID/$ACCOUNT_ID/g" | sed "s/REGION/$REGION/g" | kubectl apply -f -

# Apply ingress
echo "Applying ingress..."
kubectl apply -f k8s/simple-ingress.yaml

echo -e "\n✅ Deployments applied successfully!"
echo "It may take a few minutes for the ingress to be provisioned and DNS to be ready."

# Wait for pods to be ready
echo -e "\n===== Waiting for pods to be ready ====="
kubectl wait --for=condition=ready pod -l app=user-service --timeout=120s || echo "⚠️  Timeout waiting for user-service pods"
kubectl wait --for=condition=ready pod -l app=workflow-service --timeout=120s || echo "⚠️  Timeout waiting for workflow-service pods"

# Show deployment status
echo -e "\n===== Deployment Status ====="
echo -e "\nServices:"
kubectl get svc

echo -e "\nPods:"
kubectl get pods

echo -e "\nIngress:"
kubectl get ingress

# Wait for ingress to be provisioned
echo -e "\n===== Waiting for ingress to be provisioned ====="
echo "This may take several minutes..."

attempts=0
max_attempts=10
while [ $attempts -lt $max_attempts ]; do
  echo "Checking ALB status (attempt $((attempts+1))/$max_attempts)..."
  ALB_HOSTNAME=$(kubectl get ingress app-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
  if [ -n "$ALB_HOSTNAME" ]; then
    echo -e "\n✅ Application Load Balancer provisioned successfully!"
    echo -e "\nAccess your services at:"
    echo "- User Service: http://$ALB_HOSTNAME/api/user"
    echo "- Workflow Service: http://$ALB_HOSTNAME/api/workflow"
    break
  fi
  attempts=$((attempts+1))
  if [ $attempts -eq $max_attempts ]; then
    echo -e "\n⚠️  ALB not yet provisioned. Check status later with:"
    echo "kubectl get ingress app-ingress"
  else
    echo "ALB not ready yet. Waiting 30 seconds..."
    sleep 30
  fi
done

echo -e "\n===== Deployment Complete =====" 