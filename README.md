# NestJS Microservices on EKS

This repository contains two NestJS microservices (User and Workflow) configured for deployment on Amazon EKS with CI/CD.

## Project Structure

```
.
├── app/
│   ├── user/            # User service
│   └── workflow/        # Workflow service
├── k8s/                 # Kubernetes manifests
├── .github/workflows/   # GitHub Actions CI/CD workflows
└── eks-cluster.yaml     # EKS cluster configuration
```

## Services

### User Service
- Port: 3000
- Endpoint: `/api/user`

### Workflow Service
- Port: 3001
- Endpoint: `/api/workflow`

## Local Development

To run the user service locally:

```bash
cd app/user
npm install
npm run start:dev
```

To run the workflow service locally:

```bash
cd app/workflow
npm install
npm run start:dev
```

## CI/CD with GitHub Actions

The deployment process is fully automated using GitHub Actions workflows:

### Deployment Process

2. **Create ECR Repositories**
   - Creates ECR repositories for both user and workflow services if they don't exist
   - Triggered automatically as part of the CI/CD workflows
   - Example command:
     ```bash
     aws ecr create-repository --repository-name user-service --region ap-south-1
     aws ecr create-repository --repository-name workflow-service --region ap-south-1
     ```
3. **Tag Subnets**
   - Tag private subnets for the AWS Load Balancer Controller
   - Required for proper subnet discovery
   - Example commands:
     ```bash

     // Tag public subnets (for internet-facing load balancers)
     
     aws ec2 create-tags \
       --resources subnet-id1 subnet-id2 subnet-id3 \
       --tags Key=kubernetes.io/cluster/my-eks-cluster,Value=owned \
              Key=kubernetes.io/role/internal-elb,Value=1

    // Tag private subnets (for internal load balancers)

     aws ec2 create-tags \
       --resources subnet-id4 subnet-id5 subnet-id6 \
       --tags Key=kubernetes.io/cluster/my-eks-cluster,Value=owned \
              Key=kubernetes.io/role/elb,Value=1
     ```


1. **EKS Cluster Setup**
   - Creates the EKS cluster in ap-south-1 region
   - Configures AWS Load Balancer Controller
   - Triggered manually or when `eks-cluster.yaml` is updated

2. **User Service CI/CD**
   - Builds and pushes the user service Docker image to ECR
   - Deploys the user service to EKS
   - Triggered when changes are made to the user service code or deployment files

3. **Workflow Service CI/CD**
   - Builds and pushes the workflow service Docker image to ECR
   - Deploys the workflow service to EKS
   - Triggered when changes are made to the workflow service code or deployment files

## Deployment Steps

1. **Set up AWS credentials in GitHub Secrets**
   - Add `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` with appropriate permissions for ECR and EKS

2. **Run the EKS Cluster Setup workflow**
   - Go to the Actions tab in GitHub
   - Select "EKS Cluster Setup" workflow
   - Click "Run workflow"
   - Wait for the EKS cluster to be created (this may take 15-20 minutes)

3. **Push changes to the main branch**
   - Changes to the user service will trigger the User Service CI/CD workflow
   - Changes to the workflow service will trigger the Workflow Service CI/CD workflow

## Monitoring Deployments

After deployment, you can access the services via the ALB Ingress:
- User Service: `http://<ALB_DNS>/api/user`
- Workflow Service: `http://<ALB_DNS>/api/workflow`

To get the ALB DNS:

```bash
kubectl get ingress app-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

## Prerequisites for AWS Deployment

1. AWS account with permissions for:
   - ECR repository creation and image push
   - EKS cluster creation and management
   - IAM role creation
   - VPC and networking resources creation

2. GitHub repository secrets:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY` 