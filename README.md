# NestJS Microservices on EKS

This repository contains two NestJS microservices (User and Workflow) configured for deployment on Amazon EKS with CI/CD.

## Project Structure

```
.
├── app/
│   ├── user/            # User service
│   └── workflow/        # Workflow service
├── k8s/                 # Kubernetes manifests
│   ├── user-deployment.yaml
│   ├── workflow-deployment.yaml
│   └── simple-ingress.yaml
├── .github/workflows/   # GitHub Actions CI/CD workflows
├── eks-cluster.yaml     # EKS cluster configuration
├── create-eks-cluster.sh  # Script to create the EKS cluster
├── delete-eks-cluster.sh  # Script to delete the EKS cluster
└── deploy.sh              # Complete deployment script
```

## Prerequisites

- AWS CLI installed and configured
- kubectl installed
- eksctl installed
- Helm installed
- Docker installed (for local development)
- Node.js and npm installed (for local development)
- GitHub account with a repository for the project

## 1. Local Development

### User Service

```bash
cd app/user
npm install
npm run start:dev
```

### Workflow Service

```bash
cd app/workflow
npm install
npm run start:dev
```

## 2. AWS Setup

### 2.1 Create IAM User

1. Create an IAM user with programmatic access
2. Attach the following policies:
   - AmazonECR-FullAccess
   - AmazonEKSClusterPolicy
   - IAMFullAccess
   - AmazonVPCFullAccess

3. Save the Access Key ID and Secret Access Key

### 2.2 Configure AWS CLI

```bash
aws configure
# Enter your Access Key ID, Secret Access Key, and default region (ap-south-1)
```

### 2.3 Create ECR Repositories

The deploy.sh script will automatically create ECR repositories if they don't exist.

## 3. EKS Cluster Setup

### 3.1 Review the EKS Configuration

Review and modify the `eks-cluster.yaml` file if needed:

- Make sure `region` is set to your desired region (ap-south-1)
- Ensure `instanceType` is at least `t3.medium` to have enough capacity for all pods

### 3.2 Prepare the Scripts

Make the scripts executable:

```bash
chmod +x create-eks-cluster.sh delete-eks-cluster.sh deploy.sh
```

### 3.3 Create the EKS Cluster

```bash
./create-eks-cluster.sh
```

This process takes approximately 15-20 minutes.

### 3.4 Verify the Cluster

```bash
kubectl get nodes
```

## 4. Deploy to EKS

Use the all-in-one deployment script:

```bash
./deploy.sh
```

This script will:
1. Check if the EKS cluster exists, and create it if needed
2. Build and push Docker images to ECR
3. Deploy the applications to Kubernetes
4. Configure the ingress for access

### 4.1 Access the Applications

After the deployment completes, the script will output the ALB DNS name. You can access the services at:
- User Service: `http://<ALB_DNS>/api/user`
- Workflow Service: `http://<ALB_DNS>/api/workflow`

If you need to manually check the ingress address later:
```bash
kubectl get ingress app-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

## 5. Clean Up

When you're done, you can delete all resources:

```bash
./delete-eks-cluster.sh
```

## 6. GitHub CI/CD Setup

### 6.1 Create GitHub Personal Access Token

1. Go to GitHub → Settings → Developer settings → Personal access tokens
2. Generate a new token with the `repo` and `workflow` scopes

### 6.2 Set Up GitHub Repository

1. Create a new GitHub repository
2. Push your code to the repository:

```bash
git init
git add .
git commit -m "Initial commit"
git branch -M main
git remote add origin https://github.com/yourusername/your-repo.git
git push -u origin main
```

### 6.3 Set Up GitHub Secrets

1. Go to your GitHub repository → Settings → Secrets and variables → Actions
2. Add the following secrets:
   - `AWS_ACCESS_KEY_ID`: Your AWS IAM user access key
   - `AWS_SECRET_ACCESS_KEY`: Your AWS IAM user secret key

## Troubleshooting

### Pods Stuck in Pending State

If pods are stuck in 'Pending' state with "Too many pods" error:

1. Check your instance type: Ensure you're using at least t3.medium instances
2. Scale up your node group:
   ```bash
   eksctl scale nodegroup --cluster my-eks-cluster --name ng-medium --nodes 3 --region ap-south-1
   ```

### AWS Load Balancer Controller Issues

If the ALB is not provisioning correctly:

1. Check the controller logs:
   ```bash
   kubectl logs -n kube-system deployment/aws-load-balancer-controller
   ```

2. Make sure your subnets are properly tagged:
   - Public subnets: `kubernetes.io/role/elb=1`
   - Private subnets: `kubernetes.io/role/internal-elb=1`
   - All subnets: `kubernetes.io/cluster/my-eks-cluster=shared`

3. Check for IAM permissions issues:
   ```bash
   eksctl get iamserviceaccount --cluster my-eks-cluster --region ap-south-1
   ```

## Services

### User Service
- Port: 3000
- Endpoint: `/api/user`

### Workflow Service
- Port: 3001
- Endpoint: `/api/workflow` 