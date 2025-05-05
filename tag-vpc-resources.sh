#!/bin/bash

# Exit on error
set -e

CLUSTER_NAME="my-eks-cluster"
REGION="ap-south-1"

echo "===== Tagging VPC Resources for EKS and AWS Load Balancer Controller ====="
echo "Using EKS Cluster Name: $CLUSTER_NAME"
echo "Using Region: $REGION"

# Get VPC ID from EKS cluster
echo "Finding VPC ID from EKS cluster..."
VPC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query "cluster.resourcesVpcConfig.vpcId" --output text)

if [ -z "$VPC_ID" ]; then
  echo "❌ Failed to get VPC ID"
  exit 1
fi

echo "✅ Found VPC ID: $VPC_ID"

# Tag the VPC itself
echo "Tagging VPC $VPC_ID..."
aws ec2 create-tags --resources $VPC_ID --tags "Key=kubernetes.io/cluster/$CLUSTER_NAME,Value=shared" --region $REGION

# Get all subnets in the VPC
echo "Finding subnets in VPC $VPC_ID..."
SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query "Subnets[*].SubnetId" --output text --region $REGION)

if [ -z "$SUBNET_IDS" ]; then
  echo "❌ No subnets found in VPC $VPC_ID"
  exit 1
fi

echo "✅ Found subnets: $SUBNET_IDS"

# Identify and tag public and private subnets
for SUBNET_ID in $SUBNET_IDS; do
  # Get subnet attributes
  SUBNET_INFO=$(aws ec2 describe-subnets --subnet-ids $SUBNET_ID --query "Subnets[0]" --region $REGION)
  SUBNET_NAME=$(echo $SUBNET_INFO | jq -r '.Tags[] | select(.Key=="Name") | .Value' 2>/dev/null || echo "unnamed")
  
  # Check if this is a public subnet (has a route to internet gateway)
  ROUTE_TABLE_ID=$(aws ec2 describe-route-tables --filters "Name=association.subnet-id,Values=$SUBNET_ID" --query "RouteTables[0].RouteTableId" --output text --region $REGION)
  
  if [ "$ROUTE_TABLE_ID" != "None" ]; then
    HAS_IGW=$(aws ec2 describe-route-tables --route-table-ids $ROUTE_TABLE_ID --query "RouteTables[0].Routes[?GatewayId!=null && GatewayId.starts_with('igw-')].GatewayId" --output text --region $REGION)
    
    if [ -n "$HAS_IGW" ]; then
      echo "Tagging public subnet $SUBNET_ID ($SUBNET_NAME)"
      aws ec2 create-tags --resources $SUBNET_ID --tags \
        "Key=kubernetes.io/role/elb,Value=1" \
        "Key=kubernetes.io/cluster/$CLUSTER_NAME,Value=shared" \
        --region $REGION
    else
      echo "Tagging private subnet $SUBNET_ID ($SUBNET_NAME)"
      aws ec2 create-tags --resources $SUBNET_ID --tags \
        "Key=kubernetes.io/role/internal-elb,Value=1" \
        "Key=kubernetes.io/cluster/$CLUSTER_NAME,Value=shared" \
        --region $REGION
    fi
  else
    echo "⚠️ No route table found for subnet $SUBNET_ID ($SUBNET_NAME)"
  fi
done

# Tag security groups
echo "Finding security groups in VPC $VPC_ID..."
SG_IDS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --query "SecurityGroups[*].GroupId" --output text --region $REGION)

if [ -n "$SG_IDS" ]; then
  echo "✅ Found security groups: $SG_IDS"
  
  for SG_ID in $SG_IDS; do
    SG_NAME=$(aws ec2 describe-security-groups --group-ids $SG_ID --query "SecurityGroups[0].GroupName" --output text --region $REGION)
    echo "Tagging security group $SG_ID ($SG_NAME)"
    aws ec2 create-tags --resources $SG_ID --tags "Key=kubernetes.io/cluster/$CLUSTER_NAME,Value=owned" --region $REGION
  done
fi

# Tag route tables
echo "Finding route tables in VPC $VPC_ID..."
RT_IDS=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" --query "RouteTables[*].RouteTableId" --output text --region $REGION)

if [ -n "$RT_IDS" ]; then
  echo "✅ Found route tables: $RT_IDS"
  
  for RT_ID in $RT_IDS; do
    echo "Tagging route table $RT_ID"
    aws ec2 create-tags --resources $RT_ID --tags "Key=kubernetes.io/cluster/$CLUSTER_NAME,Value=shared" --region $REGION
  done
fi

echo "===== VPC Resource Tagging Complete ====="
echo "✅ VPC and all subnets tagged for EKS and AWS Load Balancer Controller"
echo "✅ Security groups and route tables tagged"
echo ""
echo "You can now check if the AWS Load Balancer Controller works correctly by deploying:"
echo "kubectl apply -f k8s/simple-ingress.yaml" 